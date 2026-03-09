import AppKit
import Combine
import Foundation

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var isPresented = false
    @Published var query = "" {
        didSet { updateFilteredAppsCache() }
    }
    @Published private(set) var apps: [AppItem] = [] {
        didSet { updateFilteredAppsCache() }
    }
    @Published private(set) var isRefreshing = false
    @Published var shouldFocusSearchField = false
    @Published var showSettings = false
    @Published private(set) var filteredAppsCache: [AppItem] = []

    let settingsStore: SettingsStore
    private let recentAppsStore = RecentAppsStore()
    private var cancellables = Set<AnyCancellable>()

    init(settingsStore: SettingsStore = .shared) {
        self.settingsStore = settingsStore

        settingsStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.objectWillChange.send()
                self?.updateFilteredAppsCache()
            }
            .store(in: &cancellables)
    }

    var filteredApps: [AppItem] {
        filteredAppsCache
    }

    var spotlightResult: AppItem? {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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

    var subtitleText: String {
        if isRefreshing {
            return "正在扫描应用..."
        }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(settingsStore.sortMode.displayName)，共 \(apps.count) 个应用"
        }
        return "搜索结果 \(filteredAppsCache.count) 个"
    }

    private func updateFilteredAppsCache() {
        let hasQuery = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let ranked = apps.compactMap { app -> (app: AppItem, score: Int, recency: TimeInterval, count: Int)? in
            let recency = recentAppsStore.lastLaunchTimestamp(for: app)
            let count = recentAppsStore.launchCount(for: app)

            guard hasQuery else {
                return (app, 0, recency, count)
            }
            guard let score = SearchScorer.score(app: app, query: query) else {
                return nil
            }
            return (app, score, recency, count)
        }

        let result: [AppItem]
        if hasQuery {
            result = ranked.sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.recency != rhs.recency { return lhs.recency > rhs.recency }
                return lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
            }.map(\.app)
        } else {
            switch settingsStore.sortMode {
            case .recent:
                result = ranked.sorted { lhs, rhs in
                    if lhs.recency != rhs.recency { return lhs.recency > rhs.recency }
                    return lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
                }.map(\.app)
            case .alpha:
                result = ranked.sorted { lhs, rhs in
                    lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
                }.map(\.app)
            case .frequency:
                result = ranked.sorted { lhs, rhs in
                    if lhs.count != rhs.count { return lhs.count > rhs.count }
                    if lhs.recency != rhs.recency { return lhs.recency > rhs.recency }
                    return lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
                }.map(\.app)
            case .manual:
                let order = settingsStore.manualAppOrder
                let orderMap = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
                result = ranked.sorted { lhs, rhs in
                    let li = orderMap[lhs.app.id] ?? Int.max
                    let ri = orderMap[rhs.app.id] ?? Int.max
                    if li != ri { return li < ri }
                    return lhs.app.name.localizedStandardCompare(rhs.app.name) == .orderedAscending
                }.map(\.app)
            }
        }
        filteredAppsCache = result
    }

    func deferredPrepare() {
        if apps.isEmpty {
            if let cached = AppScanner().loadCachedApplications() {
                apps = cached
                AppIconProvider.shared.preload(apps: cached, limit: 80)
            }
            refreshApplications()
        } else {
            AppIconProvider.shared.preload(apps: apps, limit: 80)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.shouldFocusSearchField = true
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

    func moveApps(from source: IndexSet, to destination: Int) {
        var order = gridApps.map(\.id)
        order.move(fromOffsets: source, toOffset: destination)
        settingsStore.manualAppOrder = order
        if settingsStore.sortMode != .manual {
            settingsStore.sortMode = .manual
        }
    }
}
