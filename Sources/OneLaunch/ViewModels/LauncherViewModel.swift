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

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var isPresented = false
    @Published var query = "" {
        didSet {
            if query != oldValue {
                activeFolderID = nil
                currentPage = 0
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
    @Published private(set) var filteredAppsCache: [AppItem] = []
    @Published var activeFolderID: String?
    @Published var currentPage = 0

    let settingsStore: SettingsStore
    let itemsPerPage = 36
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
    }

    var filteredApps: [AppItem] {
        filteredAppsCache
    }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var spotlightResult: AppItem? {
        guard isSearching else {
            return nil
        }
        return filteredAppsCache.first
    }

    var gridApps: [AppItem] {
        guard let spotlightResult else {
            return filteredAppsCache
        }
        return filteredAppsCache.filter { $0.id != spotlightResult.id }
    }

    var folderDisplays: [FolderDisplay] {
        resolveFolders(for: gridApps)
    }

    var gridItems: [LauncherGridItem] {
        let apps = gridApps
        guard !isSearching else {
            return apps.map { .app($0) }
        }

        let folderMap = Dictionary(
            folderDisplays.flatMap { display in
                display.apps.map { ($0.id, display) }
            },
            uniquingKeysWith: { existing, _ in existing }
        )

        var seenFolders = Set<String>()
        var result: [LauncherGridItem] = []

        for app in apps {
            if let folder = folderMap[app.id] {
                if seenFolders.insert(folder.id).inserted {
                    result.append(.folder(folder))
                }
            } else {
                result.append(.app(app))
            }
        }

        return result
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
        return "搜索结果 \(filteredAppsCache.count) 个"
    }

    private func updateFilteredAppsCache() {
        let appsCopy = apps
        let queryCopy = query
        let sortMode = settingsStore.sortMode
        let manualOrder = settingsStore.manualAppOrder
        let hasQuery = !queryCopy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // 仅在首屏/数据源发生明显变化时先用原始列表兜底，避免拖拽排序时先闪回原始顺序。
        let shouldPrimeVisibleApps = !hasQuery
            && !appsCopy.isEmpty
            && (filteredAppsCache.isEmpty || (sortMode != .manual && filteredAppsCache.count != appsCopy.count))

        if shouldPrimeVisibleApps {
            filteredAppsCache = appsCopy
        }

        Task.detached(priority: .userInitiated) {
            let result = LauncherViewModel.computeFilteredApps(apps: appsCopy, query: queryCopy, sortMode: sortMode, manualOrder: manualOrder)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if self.apps == appsCopy && self.query == queryCopy {
                    self.filteredAppsCache = result
                }
            }
        }
    }

    /// 在后台线程执行，用于避免主线程卡顿（UserDefaults 读取 + 排序）
    private nonisolated static func computeFilteredApps(apps: [AppItem], query: String, sortMode: SortMode, manualOrder: [String]) -> [AppItem] {
        let hasQuery = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let store = RecentAppsStore()

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

        if !hasPreparedData {
            hasPreparedData = true

            if apps.isEmpty {
                // 先显示缓存数据，让用户立即看到界面
                if let cached = AppScanner().loadCachedApplications() {
                    apps = cached
                    // 延迟预加载图标，避免阻塞主线程
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        AppIconProvider.shared.preload(apps: cached, limit: 60)
                    }
                }
                // 后台刷新应用列表
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.refreshApplications()
                }
            } else {
                // 延迟预加载，优先保证动画流畅
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    AppIconProvider.shared.preload(apps: self.apps, limit: 60)
                }
            }
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

    func clearSearch() {
        query = ""
        shouldFocusSearchField = true
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
        guard let app = filteredApps.first else {
            return
        }

        launch(app)
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

        filteredAppsCache = orderedApps + remainingApps.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func resolveFolders(for visibleApps: [AppItem]) -> [FolderDisplay] {
        let appByID = Dictionary(
            visibleApps.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        return normalizedFolders(settingsStore.appFolders).compactMap { folder in
            // 文件夹内顺序由 folder.appIDs 决定（支持手动拖拽排序）
            let members = folder.appIDs.compactMap { appByID[$0] }
            guard members.count >= 2 else { return nil }
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

            guard cleanIDs.count >= 2 else { continue }
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
