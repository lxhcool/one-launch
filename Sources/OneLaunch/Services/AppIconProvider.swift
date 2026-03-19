import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppIconProvider: ObservableObject {
    static let shared = AppIconProvider()

    @Published private(set) var cacheVersion = 0
    private var cache: [String: NSImage] = [:]
    private var inFlight: Set<String> = []
    private let placeholderIcon: NSImage

    private init() {
        let image = NSWorkspace.shared.icon(for: .application)
        image.size = NSSize(width: 64, height: 64)
        placeholderIcon = image
    }

    func icon(for app: AppItem) -> NSImage {
        let path = app.url.path

        if let cachedImage = cache[path] {
            return cachedImage
        }

        if !inFlight.contains(path) {
            inFlight.insert(path)
            loadSingleIcon(path: path)
        }

        return placeholderIcon
    }

    /// 在后台预加载前 N 个应用图标，减轻首次打开列表时的卡顿
    func preload(apps: [AppItem], limit: Int = 80) {
        let candidatePaths = apps.prefix(limit).map(\.url.path)
        let toLoadPaths = candidatePaths.filter { path in
            cache[path] == nil && !inFlight.contains(path)
        }
        guard !toLoadPaths.isEmpty else { return }

        for path in toLoadPaths {
            inFlight.insert(path)
        }

        Task.detached(priority: .utility) {
            let loaded: [(String, NSImage)] = toLoadPaths.map { path in
                let img = NSWorkspace.shared.icon(forFile: path)
                img.size = NSSize(width: 64, height: 64)
                return (path, img)
            }
            await MainActor.run {
                AppIconProvider.shared.setCachedImages(loaded)
            }
        }
    }

    private func setCachedImages(_ pairs: [(String, NSImage)]) {
        var didChange = false
        for (path, img) in pairs {
            if cache[path] == nil {
                didChange = true
            }
            cache[path] = img
            inFlight.remove(path)
        }

        if didChange {
            cacheVersion &+= 1
        }
    }

    private func loadSingleIcon(path: String) {
        Task.detached(priority: .utility) {
            let img = NSWorkspace.shared.icon(forFile: path)
            img.size = NSSize(width: 64, height: 64)
            await MainActor.run {
                AppIconProvider.shared.setCachedImages([(path, img)])
            }
        }
    }
}
