import AppKit
import Combine
import Foundation

enum FolderDropTarget: Hashable {
    case app(String)
    case folder(String)
}

struct FolderDisplay: Identifiable, Hashable {
    let folder: AppFolder
    let apps: [AppItem]

    var id: String {
        folder.id
    }
}

enum LauncherGridItem: Identifiable, Hashable {
    case app(AppItem)
    case folder(FolderDisplay)

    var id: String {
        switch self {
        case let .app(app):
            return app.id
        case let .folder(folder):
            return "folder:\(folder.id)"
        }
    }
}

/// 一次性承载所有网格缓存，减少 @Published 触发次数
struct GridCache {
    var filteredApps: [AppItem] = []
    var gridApps: [AppItem] = []
    var pinnedApps: [AppItem] = []
    var folderDisplays: [FolderDisplay] = []
    var gridItems: [LauncherGridItem] = []
}

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var isPresented = false
    @Published var scale: CGFloat = 1.0
    @Published var isPanelTransitioning = false
    @Published var query = "" {
        didSet {
            if query != oldValue {
                activeFolderID = nil
                searchSelectedIndex = 0
            }
            updateFilteredAppsCache()
        }
    }
    @Published private(set) var apps: [AppItem] = [] {
        didSet {
            updateFilteredAppsCache()
            activeFolderID = nil
        }
    }
    @Published private(set) var isRefreshing = false
    @Published var shouldFocusSearchField = false
    @Published var showSettings = false
    @Published private(set) var gridCache = GridCache()
    @Published var activeFolderID: String?
    @Published var currentPage = 0
    @Published var searchSelectedIndex: Int = 0

    let settingsStore: SettingsStore
    let itemsPerPage = 45
    let maxSearchResults = 8
    private let recentAppsStore = RecentAppsStore()
    private var cancellables = Set<AnyCancellable>()
    private var hasPreparedData = false

    init(settingsStore: SettingsStore? = nil) {
        let resolvedSettingsStore = settingsStore ?? .shared
        self.settingsStore = resolvedSettingsStore

        Publishers.CombineLatest(
            resolvedSettingsStore.$sortMode.removeDuplicates(),
            resolvedSettingsStore.$manualAppOrder.removeDuplicates()
        )
        .dropFirst()
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.updateFilteredAppsCache()
        }
        .store(in: &cancellables)

        resolvedSettingsStore.$appFolders
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateFoldersInCache()
            }
            .store(in: &cancellables)

        resolvedSettingsStore.$pinnedAppIDs
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updatePinnedAppsInCache()
            }
            .store(in: &cancellables)
    }

    var filteredApps: [AppItem] { gridCache.filteredApps }
    var gridApps: [AppItem] { gridCache.gridApps }
    var folderDisplays: [FolderDisplay] { gridCache.folderDisplays }
    var pinnedApps: [AppItem] { gridCache.pinnedApps }
    var gridItems: [LauncherGridItem] { gridCache.gridItems }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var spotlightResult: AppItem? {
        guard isSearching else {
            return nil
        }
        return gridCache.filteredApps.first
    }

    var searchResults: [AppItem] {
        guard isSearching else { return [] }
        return Array(gridCache.filteredApps.prefix(maxSearchResults))
    }

    var totalPages: Int {
        max(1, (gridItems.count + itemsPerPage - 1) / itemsPerPage)
    }

    func gridItemsForPage(_ page: Int) -> [LauncherGridItem] {
        let allItems = gridItems
        let start = page * itemsPerPage
        let end = min(start + itemsPerPage, allItems.count)
        guard start < allItems.count else { return [] }
        return Array(allItems[start..<end])
    }

    var presentedFolder: FolderDisplay? {
        guard let activeFolderID else { return nil }
        return folderDisplays.first { $0.id == activeFolderID }
    }

    var subtitleText: String {
        if isRefreshing {
            return "正在扫描应用..."
        }
        if !isSearching {
            return "\(settingsStore.sortMode.displayName)，共 \(apps.count) 个应用"
        }
        return "搜索结果 \(gridCache.filteredApps.count) 个"
    }

    private var searchDebounceTask: Task<Void, Never>?

    private func updateFilteredAppsCache() {
        let appsCopy = apps
        let queryCopy = query
        let sortMode = settingsStore.sortMode
        let manualOrder = settingsStore.manualAppOrder
        let hasQuery = !queryCopy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // 取消之前的搜索任务
        searchDebounceTask?.cancel()

        // 清空搜索时同步计算，避免异步 context switch 导致的列表闪现
        if !hasQuery {
            let filtered = LauncherViewModel.computeFilteredApps(
                apps: appsCopy, query: "", sortMode: sortMode, manualOrder: manualOrder, store: recentAppsStore
            )
            gridCache = buildGridCache(gridApps: filtered, filteredApps: filtered)
            return
        }

        // 清空旧搜索结果，防止异步计算完成前用旧数据渲染
        gridCache.filteredApps = []

        // SearchField 已做 30ms 合并，这里直接异步计算搜索
        searchDebounceTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }

            // 在后台线程计算搜索和排序结果（使用缓存的 store 避免重复读 UserDefaults）
            let result = await Task.detached(priority: .userInitiated) { [store = self.recentAppsStore] in
                let filtered = LauncherViewModel.computeFilteredApps(
                    apps: appsCopy,
                    query: queryCopy,
                    sortMode: sortMode,
                    manualOrder: manualOrder,
                    store: store
                )
                let grid: [AppItem]
                if hasQuery {
                    grid = LauncherViewModel.computeFilteredApps(
                        apps: appsCopy,
                        query: "",
                        sortMode: sortMode,
                        manualOrder: manualOrder,
                        store: store
                    )
                } else {
                    grid = filtered
                }
                return (filtered: filtered, grid: grid)
            }.value

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.apps == appsCopy && self.query == queryCopy else { return }
                self.gridCache = self.buildGridCache(gridApps: result.grid, filteredApps: result.filtered)
            }
        }
    }

    /// 构建完整的网格缓存，单次 @Published 赋值
    private func buildGridCache(gridApps: [AppItem], filteredApps: [AppItem]) -> GridCache {
        let pinnedIDs = Set(settingsStore.pinnedAppIDs)
        let appByID = Dictionary(
            gridApps.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let pinnedApps = settingsStore.pinnedAppIDs.compactMap { appByID[$0] }
        let scrollableApps = gridApps.filter { !pinnedIDs.contains($0.id) }
        let displays = resolveFolders(for: scrollableApps)
        let items = buildGridItems(from: scrollableApps, folderDisplays: displays)

        let maxPage = max(0, (items.count + itemsPerPage - 1) / itemsPerPage - 1)
        if currentPage > maxPage {
            currentPage = maxPage
        }

        if let activeFolderID, !displays.contains(where: { $0.id == activeFolderID }) {
            self.activeFolderID = nil
        }

        return GridCache(
            filteredApps: filteredApps,
            gridApps: gridApps,
            pinnedApps: pinnedApps,
            folderDisplays: displays,
            gridItems: items
        )
    }

    /// 仅更新置顶应用（不重新解析文件夹）
    private func updatePinnedAppsInCache() {
        var cache = gridCache
        let pinnedIDs = Set(settingsStore.pinnedAppIDs)
        let appByID = Dictionary(cache.gridApps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        cache.pinnedApps = settingsStore.pinnedAppIDs.compactMap { appByID[$0] }
        let scrollableApps = cache.gridApps.filter { !pinnedIDs.contains($0.id) }
        cache.gridItems = buildGridItems(from: scrollableApps, folderDisplays: cache.folderDisplays)
        gridCache = cache
    }

    /// 仅更新文件夹展示（不重新解析置顶应用）
    private func updateFoldersInCache() {
        var cache = gridCache
        let pinnedIDs = Set(settingsStore.pinnedAppIDs)
        let scrollableApps = cache.gridApps.filter { !pinnedIDs.contains($0.id) }
        cache.folderDisplays = resolveFolders(for: scrollableApps)
        cache.gridItems = buildGridItems(from: scrollableApps, folderDisplays: cache.folderDisplays)

        if let activeFolderID, !cache.folderDisplays.contains(where: { $0.id == activeFolderID }) {
            self.activeFolderID = nil
        }

        gridCache = cache
    }

    /// 将可滚动应用列表与文件夹合并为 LauncherGridItem 数组
    private func buildGridItems(from scrollableApps: [AppItem], folderDisplays: [FolderDisplay]) -> [LauncherGridItem] {
        let folderMap = Dictionary(
            folderDisplays.flatMap { display in display.apps.map { ($0.id, display) } },
            uniquingKeysWith: { a, _ in a }
        )
        var seenFolders = Set<String>()
        var items: [LauncherGridItem] = []
        for app in scrollableApps {
            if let folder = folderMap[app.id] {
                if seenFolders.insert(folder.id).inserted {
                    items.append(.folder(folder))
                }
            } else {
                items.append(.app(app))
            }
        }
        return items
    }

    /// 在后台线程执行，用于避免主线程卡顿（UserDefaults 读取 + 排序）
    private nonisolated static func computeFilteredApps(apps: [AppItem], query: String, sortMode: SortMode, manualOrder: [String], store: RecentAppsStore) -> [AppItem] {
        let hasQuery = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let ranked = apps.compactMap { app -> (app: AppItem, score: Int, recency: TimeInterval, count: Int)? in
            let recency = store.lastLaunchTimestamp(for: app)
            let count = store.launchCount(for: app)
            guard hasQuery else { return (app, 0, recency, count) }
            guard let score = SearchScorer.score(app: app, query: query) else { return nil }
            return (app, score, recency, count)
        }

        if hasQuery {
            return ranked.sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.recency != rhs.recency { return lhs.recency > rhs.recency }
                return lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
            }.map(\.app)
        }
        switch sortMode {
        case .recent:
            return ranked.sorted { lhs, rhs in
                if lhs.recency != rhs.recency { return lhs.recency > rhs.recency }
                return lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
            }.map(\.app)
        case .alpha:
            return ranked.sorted { lhs, rhs in
                lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
            }.map(\.app)
        case .frequency:
            return ranked.sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                if lhs.recency != rhs.recency { return lhs.recency > rhs.recency }
                return lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
            }.map(\.app)
        case .manual:
            let orderMap = Dictionary(
                manualOrder.enumerated().map { ($1, $0) },
                uniquingKeysWith: { existing, _ in existing }
            )
            return ranked.sorted { lhs, rhs in
                let li = orderMap[lhs.app.id] ?? Int.max
                let ri = orderMap[rhs.app.id] ?? Int.max
                if li != ri { return li < ri }
                return lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
            }.map(\.app)
        }
    }

    func deferredPrepare() {
        // 立即聚焦搜索框，不等待数据加载
        DispatchQueue.main.async {
            self.shouldFocusSearchField = true
        }

        guard !hasPreparedData else {
            if !apps.isEmpty {
                // 延迟预加载，优先保证动画流畅
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    AppIconProvider.shared.preload(apps: self.apps, limit: 60)
                }
            }
            return
        }

        hasPreparedData = true

        if apps.isEmpty {
            // 异步读取缓存，避免首次展示阻塞主线程
            Task.detached(priority: .userInitiated) { [weak self] in
                let cached = AppScanner().loadCachedApplications()
                guard let self, let cached, !cached.isEmpty else { return }
                await MainActor.run {
                    guard self.apps.isEmpty else { return }
                    self.apps = cached
                    // 延迟预加载图标，避免阻塞主线程
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        AppIconProvider.shared.preload(apps: cached, limit: 60)
                    }
                }
            }
        } else {
            // 延迟预加载，优先保证动画流畅
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                AppIconProvider.shared.preload(apps: self.apps, limit: 60)
            }
        }

        // 后台刷新应用列表
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshApplications()
        }
    }

    func refreshApplications() {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true

        Task {
            let scannedApps = await Task.detached(priority: .userInitiated) {
                AppScanner().scanApplications()
            }.value

            apps = scannedApps
            AppIconProvider.shared.preload(apps: scannedApps, limit: 80)
            isRefreshing = false
        }
    }

    /// 静默刷新：不显示加载状态，仅在应用列表实际变化时才更新 UI
    func silentRefreshApplications() {
        guard !isRefreshing else { return }

        isRefreshing = true

        Task {
            let scannedApps = await Task.detached(priority: .background) {
                AppScanner().scanApplications()
            }.value

            // 仅在列表真正发生变化时才更新，避免不必要的 UI 重建
            let oldIDs = Set(self.apps.map(\.id))
            let newIDs = Set(scannedApps.map(\.id))
            let changed = oldIDs != newIDs

            if changed {
                self.apps = scannedApps
                AppIconProvider.shared.preload(apps: scannedApps, limit: 80)
            }

            self.isRefreshing = false
        }
    }

    func clearSearch() {
        query = ""
        shouldFocusSearchField = true
    }

    func isPinned(_ appID: String) -> Bool {
        settingsStore.isAppPinned(appID)
    }

    func togglePinnedState(for appID: String) {
        setPinned(appID, pinned: !isPinned(appID))
    }

    func setPinned(_ appID: String, pinned: Bool) {
        if pinned {
            removeAppFromFolderRecords(appID: appID)
        }
        settingsStore.setAppPinned(appID, pinned: pinned)
    }

    func nextPage() {
        if currentPage < totalPages - 1 {
            currentPage += 1
        }
    }

    func previousPage() {
        if currentPage > 0 {
            currentPage -= 1
        }
    }

    func launchFirstResult() {
        guard !searchResults.isEmpty else { return }
        let index = max(0, min(searchSelectedIndex, searchResults.count - 1))
        launch(searchResults[index])
    }

    func selectPreviousSearchResult() {
        guard !searchResults.isEmpty else { return }
        if searchSelectedIndex > 0 {
            searchSelectedIndex -= 1
        } else {
            searchSelectedIndex = searchResults.count - 1
        }
    }

    func selectNextSearchResult() {
        guard !searchResults.isEmpty else { return }
        if searchSelectedIndex < searchResults.count - 1 {
            searchSelectedIndex += 1
        } else {
            searchSelectedIndex = 0
        }
    }

    func launch(_ app: AppItem) {
        recentAppsStore.recordLaunch(for: app)
        updateFilteredAppsCache()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(
            at: app.url,
            configuration: configuration
        ) { _, error in
            if let error {
                NSSound.beep()
                NSLog("Failed to launch app: \(error.localizedDescription)")
            }
        }
    }

    func openFolder(_ folderID: String) {
        activeFolderID = folderID
    }

    func closeFolder() {
        activeFolderID = nil
    }

    func dissolveFolder(_ folderID: String) {
        settingsStore.appFolders.removeAll { $0.id == folderID }
        if activeFolderID == folderID {
            activeFolderID = nil
        }
    }

    func renameFolder(_ folderID: String, to name: String) {
        guard let index = settingsStore.appFolders.firstIndex(where: { $0.id == folderID }) else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsStore.appFolders[index].name = trimmedName.isEmpty ? "新建文件夹" : trimmedName
    }

    /// 将应用从文件夹中移出，放回主网格
    func removeAppFromFolder(appID: String, folderID: String) {
        guard let index = settingsStore.appFolders.firstIndex(where: { $0.id == folderID }) else {
            return
        }

        var folders = settingsStore.appFolders
        folders[index].appIDs.removeAll { $0 == appID }

        if folders[index].appIDs.count < 2 {
            folders.remove(at: index)
        }

        settingsStore.appFolders = folders
    }

    /// 通过右键菜单将应用添加到已有文件夹
    func addAppToFolder(appID: String, folderID: String) {
        var folders = normalizedFolders(settingsStore.appFolders)
        // 先从其他文件夹中移除
        let sourceFolderID = folderContaining(appID: appID, in: folders)
        if sourceFolderID == folderID { return }
        if let sourceFolderID {
            if let idx = folders.firstIndex(where: { $0.id == sourceFolderID }) {
                folders[idx].appIDs.removeAll { $0 == appID }
                if folders[idx].appIDs.count < 2 {
                    folders.remove(at: idx)
                }
            }
        }
        appendApp(appID, toFolder: folderID, folders: &folders)
        settingsStore.appFolders = normalizedFolders(folders)
    }

    /// 通过右键菜单将应用添加到新文件夹
    func addAppToNewFolder(appID: String) {
        var folders = normalizedFolders(settingsStore.appFolders)
        let sourceFolderID = folderContaining(appID: appID, in: folders)
        if let sourceFolderID {
            if let idx = folders.firstIndex(where: { $0.id == sourceFolderID }) {
                folders[idx].appIDs.removeAll { $0 == appID }
                if folders[idx].appIDs.count < 2 {
                    folders.remove(at: idx)
                }
            }
        }
        let newFolder = AppFolder(
            id: UUID().uuidString,
            name: "新建文件夹",
            appIDs: [appID],
            isAuto: false,
            autoKey: nil
        )
        folders.append(newFolder)
        settingsStore.appFolders = normalizedFolders(folders)
    }

    func groupApp(sourceID: String, onto target: FolderDropTarget) {
        guard !isSearching else { return }
        guard apps.contains(where: { $0.id == sourceID }) else { return }

        var folders = normalizedFolders(settingsStore.appFolders)
        let sourceFolderID = folderContaining(appID: sourceID, in: folders)

        switch target {
        case let .app(targetID):
            guard sourceID != targetID else { return }
            guard apps.contains(where: { $0.id == targetID }) else { return }

            let targetFolderID = folderContaining(appID: targetID, in: folders)
            if sourceFolderID == targetFolderID, sourceFolderID != nil {
                return
            }

            if let targetFolderID {
                if let sourceFolderID, sourceFolderID != targetFolderID {
                    mergeFolder(sourceID: sourceFolderID, into: targetFolderID, folders: &folders)
                } else {
                    appendApp(sourceID, toFolder: targetFolderID, folders: &folders)
                }
            } else if let sourceFolderID {
                appendApp(targetID, toFolder: sourceFolderID, folders: &folders)
            } else {
                folders.append(
                    AppFolder(
                        id: UUID().uuidString,
                        name: "新建文件夹",
                        appIDs: [targetID, sourceID],
                        isAuto: false,
                        autoKey: nil
                    )
                )
            }

        case let .folder(targetFolderID):
            guard folderIndex(of: targetFolderID, in: folders) != nil else { return }
            if sourceFolderID == targetFolderID {
                return
            }

            if let sourceFolderID {
                mergeFolder(sourceID: sourceFolderID, into: targetFolderID, folders: &folders)
            } else {
                appendApp(sourceID, toFolder: targetFolderID, folders: &folders)
            }
        }

        settingsStore.appFolders = normalizedFolders(folders)
    }

    func moveFolder(folderID: String, onto target: FolderDropTarget) {
        guard !isSearching else { return }
        guard let sourceFolder = folderDisplays.first(where: { $0.id == folderID }) else { return }

        let sourceIDs = sourceFolder.apps.map(\.id)
        guard !sourceIDs.isEmpty else { return }

        let targetIDs = appIDs(for: target)
        guard !targetIDs.isEmpty else { return }
        if Set(targetIDs).isSubset(of: Set(sourceIDs)) {
            return
        }

        var order = gridApps.map(\.id)
        order.removeAll { sourceIDs.contains($0) }

        guard let anchorID = targetIDs.first(where: { order.contains($0) }),
              let insertIndex = order.firstIndex(of: anchorID) else {
            return
        }

        order.insert(contentsOf: sourceIDs, at: insertIndex)
        applyManualOrderImmediately(order)
        settingsStore.manualAppOrder = order
        if settingsStore.sortMode != .manual {
            settingsStore.sortMode = .manual
        }
    }

    func moveGridItem(sourceItemID: String, relativeTo targetItemID: String, placeAfter: Bool) {
        guard !isSearching else { return }
        guard sourceItemID != targetItemID else { return }

        let sourceIDs = appIDs(forGridItemID: sourceItemID)
        let targetIDs = appIDs(forGridItemID: targetItemID)

        guard !sourceIDs.isEmpty, !targetIDs.isEmpty else { return }
        if Set(targetIDs).isSubset(of: Set(sourceIDs)) {
            return
        }

        var order = gridApps.map(\.id)
        order.removeAll { sourceIDs.contains($0) }

        let visibleTargetIDs = targetIDs.filter { order.contains($0) }
        guard let anchorID = visibleTargetIDs.first,
              let firstIndex = order.firstIndex(of: anchorID) else {
            return
        }

        let insertionIndex: Int
        if placeAfter,
           let lastTargetID = visibleTargetIDs.last,
           let lastIndex = order.firstIndex(of: lastTargetID) {
            insertionIndex = lastIndex + 1
        } else {
            insertionIndex = firstIndex
        }

        order.insert(contentsOf: sourceIDs, at: insertionIndex)
        applyManualOrderImmediately(order)
        settingsStore.manualAppOrder = order
        if settingsStore.sortMode != .manual {
            settingsStore.sortMode = .manual
        }
    }

    func moveApps(from source: IndexSet, to destination: Int) {
        var order = gridApps.map(\.id)
        order.move(fromOffsets: source, toOffset: destination)
        applyManualOrderImmediately(order)
        settingsStore.manualAppOrder = order
        if settingsStore.sortMode != .manual {
            settingsStore.sortMode = .manual
        }
    }

    private func applyManualOrderImmediately(_ order: [String]) {
        guard !isSearching else { return }

        let appByID = Dictionary(
            apps.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        let orderedApps = order.compactMap { appByID[$0] }
        let remainingApps = apps.filter { !order.contains($0.id) }

        let sorted = orderedApps + remainingApps.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        gridCache = buildGridCache(gridApps: sorted, filteredApps: sorted)
    }

    func resolveFolders(for visibleApps: [AppItem]) -> [FolderDisplay] {
        let appByID = Dictionary(
            visibleApps.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        return normalizedFolders(settingsStore.appFolders).compactMap { folder in
            // 文件夹内顺序由 folder.appIDs 决定（支持手动拖拽排序）
            let members = folder.appIDs.compactMap { appByID[$0] }
            guard !members.isEmpty else { return nil }
            return FolderDisplay(folder: folder, apps: members)
        }
    }

    func moveAppInFolder(folderID: String, sourceAppID: String, relativeTo targetAppID: String, placeAfter: Bool) {
        guard sourceAppID != targetAppID else { return }
        guard let folderIndex = settingsStore.appFolders.firstIndex(where: { $0.id == folderID }) else { return }

        var folders = settingsStore.appFolders
        var ids = folders[folderIndex].appIDs

        guard let sourceIndex = ids.firstIndex(of: sourceAppID),
              let targetIndex = ids.firstIndex(of: targetAppID) else {
            return
        }

        ids.remove(at: sourceIndex)

        let targetIndexAfterRemoval = ids.firstIndex(of: targetAppID) ?? targetIndex
        let insertionIndex = placeAfter ? (targetIndexAfterRemoval + 1) : targetIndexAfterRemoval
        let safeIndex = max(0, min(insertionIndex, ids.count))
        ids.insert(sourceAppID, at: safeIndex)

        folders[folderIndex].appIDs = ids
        settingsStore.appFolders = folders
    }

    private func normalizedFolders(_ folders: [AppFolder]) -> [AppFolder] {
        let validAppIDs = Set(apps.map(\.id))
        var consumed = Set<String>()
        var normalized: [AppFolder] = []

        for folder in folders {
            var seenInFolder = Set<String>()
            var cleanIDs: [String] = []

            for appID in folder.appIDs where validAppIDs.contains(appID) {
                guard !seenInFolder.contains(appID), !consumed.contains(appID) else { continue }
                seenInFolder.insert(appID)
                cleanIDs.append(appID)
            }

            guard cleanIDs.count >= 1 else { continue }
            consumed.formUnion(cleanIDs)

            var cleanFolder = folder
            cleanFolder.appIDs = cleanIDs
            if cleanFolder.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cleanFolder.name = "新建文件夹"
            }
            normalized.append(cleanFolder)
        }

        return normalized
    }

    private func removeAppFromFolderRecords(appID: String) {
        guard let index = settingsStore.appFolders.firstIndex(where: { $0.appIDs.contains(appID) }) else {
            return
        }

        var folders = settingsStore.appFolders
        folders[index].appIDs.removeAll { $0 == appID }

        if folders[index].appIDs.count < 2 {
            folders.remove(at: index)
        }

        settingsStore.appFolders = folders
    }

    private func folderContaining(appID: String, in folders: [AppFolder]) -> String? {
        folders.first(where: { $0.appIDs.contains(appID) })?.id
    }

    private func folderIndex(of folderID: String, in folders: [AppFolder]) -> Int? {
        folders.firstIndex { $0.id == folderID }
    }

    private func appendApp(_ appID: String, toFolder folderID: String, folders: inout [AppFolder]) {
        guard let idx = folderIndex(of: folderID, in: folders) else { return }
        if !folders[idx].appIDs.contains(appID) {
            folders[idx].appIDs.append(appID)
        }
    }

    private func mergeFolder(sourceID: String, into targetID: String, folders: inout [AppFolder]) {
        guard let sourceIdx = folderIndex(of: sourceID, in: folders),
              let targetIdx = folderIndex(of: targetID, in: folders),
              sourceIdx != targetIdx else { return }

        let sourceMembers = folders[sourceIdx].appIDs
        for appID in sourceMembers where !folders[targetIdx].appIDs.contains(appID) {
            folders[targetIdx].appIDs.append(appID)
        }

        folders.remove(at: sourceIdx)
    }

    private func appIDs(for target: FolderDropTarget) -> [String] {
        switch target {
        case let .app(appID):
            return [appID]
        case let .folder(folderID):
            return folderDisplays.first(where: { $0.id == folderID })?.apps.map(\.id) ?? []
        }
    }

    private func appIDs(forGridItemID itemID: String) -> [String] {
        guard let item = gridItems.first(where: { $0.id == itemID }) else {
            return []
        }

        switch item {
        case let .app(app):
            return [app.id]
        case let .folder(folder):
            return folder.apps.map(\.id)
        }
    }
}
