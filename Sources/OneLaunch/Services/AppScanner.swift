import Foundation

struct AppScanner {
    private let fileManager = FileManager.default
    private static let cacheKey = "cachedApplications"

    func scanApplications() -> [AppItem] {
        let roots = applicationRoots()
        var discovered: [String: AppItem] = [:]

        for root in roots {
            guard fileManager.fileExists(atPath: root.path) else {
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isApplicationKey, .localizedNameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
                    continue
                }

                let resolvedURL = url.resolvingSymlinksInPath()
                let app = makeAppItem(from: resolvedURL)
                discovered[app.id] = app
            }
        }

        let result = discovered.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        saveCache(result)
        return result
    }

    func loadCachedApplications() -> [AppItem]? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else {
            return nil
        }

        guard let entries = try? JSONDecoder().decode([CachedApp].self, from: data) else {
            return nil
        }

        let apps = entries.compactMap { entry -> AppItem? in
            let url = URL(fileURLWithPath: entry.path)
            guard FileManager.default.fileExists(atPath: entry.path) else { return nil }
            let lsCategoryType = Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
            let fallbackCategory = AppCategory.resolve(
                name: entry.name,
                bundleIdentifier: entry.bundleIdentifier,
                lsCategoryType: lsCategoryType
            )
            let category = entry.category.flatMap(AppCategory.init(rawValue:)) ?? fallbackCategory
            return AppItem(url: url, name: entry.name, bundleIdentifier: entry.bundleIdentifier, category: category)
        }

        guard !apps.isEmpty else { return nil }

        var seen = Set<String>()
        let deduped = apps.filter { app in
            seen.insert(app.id).inserted
        }
        return deduped.isEmpty ? nil : deduped
    }

    private func saveCache(_ apps: [AppItem]) {
        let entries = apps.map {
            CachedApp(
                path: $0.url.path,
                name: $0.name,
                bundleIdentifier: $0.bundleIdentifier,
                category: $0.category.rawValue
            )
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    private func applicationRoots() -> [URL] {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser

        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    private func makeAppItem(from url: URL) -> AppItem {
        let bundle = Bundle(url: url)
        let localizedName = fileManager.displayName(atPath: url.path)
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let fallbackName = bundle?.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
        let name = bundleName ?? fallbackName ?? localizedName.replacingOccurrences(of: ".app", with: "")
        let bundleIdentifier = bundle?.bundleIdentifier
        let lsCategoryType = bundle?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        let category = AppCategory.resolve(name: name, bundleIdentifier: bundleIdentifier, lsCategoryType: lsCategoryType)

        return AppItem(
            url: url,
            name: name,
            bundleIdentifier: bundleIdentifier,
            category: category
        )
    }
}

private struct CachedApp: Codable {
    let path: String
    let name: String
    let bundleIdentifier: String?
    let category: String?
}
