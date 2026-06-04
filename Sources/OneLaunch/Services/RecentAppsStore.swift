import Foundation

final class RecentAppsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let storageKey = "recentApplications"
    private let countKey = "launchCounts"

    /// 内存缓存，避免每次排序都读 UserDefaults
    private var cachedRecords: [String: TimeInterval]?
    private var cachedCounts: [String: Int]?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recordLaunch(for app: AppItem) {
        var records = loadRecords()
        records[app.url.path] = Date().timeIntervalSince1970
        defaults.set(records, forKey: storageKey)
        cachedRecords = records

        var counts = loadCounts()
        counts[app.url.path] = (counts[app.url.path] ?? 0) + 1
        defaults.set(counts, forKey: countKey)
        cachedCounts = counts
    }

    func lastLaunchTimestamp(for app: AppItem) -> TimeInterval {
        loadRecords()[app.url.path] ?? 0
    }

    func launchCount(for app: AppItem) -> Int {
        loadCounts()[app.url.path] ?? 0
    }

    private func loadRecords() -> [String: TimeInterval] {
        if let cached = cachedRecords { return cached }
        let records = defaults.dictionary(forKey: storageKey) as? [String: TimeInterval] ?? [:]
        cachedRecords = records
        return records
    }

    private func loadCounts() -> [String: Int] {
        if let cached = cachedCounts { return cached }
        let counts = defaults.dictionary(forKey: countKey) as? [String: Int] ?? [:]
        cachedCounts = counts
        return counts
    }
}
