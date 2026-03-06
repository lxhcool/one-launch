import Foundation

final class RecentAppsStore {
    private let defaults: UserDefaults
    private let storageKey = "recentApplications"
    private let countKey = "launchCounts"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recordLaunch(for app: AppItem) {
        var records = loadRecords()
        records[app.url.path] = Date().timeIntervalSince1970
        defaults.set(records, forKey: storageKey)

        var counts = loadCounts()
        counts[app.url.path] = (counts[app.url.path] ?? 0) + 1
        defaults.set(counts, forKey: countKey)
    }

    func lastLaunchTimestamp(for app: AppItem) -> TimeInterval {
        loadRecords()[app.url.path] ?? 0
    }

    func launchCount(for app: AppItem) -> Int {
        loadCounts()[app.url.path] ?? 0
    }

    private func loadRecords() -> [String: TimeInterval] {
        defaults.dictionary(forKey: storageKey) as? [String: TimeInterval] ?? [:]
    }

    private func loadCounts() -> [String: Int] {
        defaults.dictionary(forKey: countKey) as? [String: Int] ?? [:]
    }
}
