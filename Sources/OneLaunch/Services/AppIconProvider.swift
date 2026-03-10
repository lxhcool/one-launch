import AppKit

@MainActor
final class AppIconProvider {
    static let shared = AppIconProvider()

    private var cache: [String: NSImage] = [:]
    private var inFlight: Set<String> = []

    private init() {}

    func icon(for app: AppItem) -> NSImage {
        let path = app.url.path

        if let cachedImage = cache[path] {
            return cachedImage
        }

        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 64, height: 64)
        cache[path] = image
        return image
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
            await MainActor.run { [weak self] in
                self?.setCachedImages(loaded)
            }
        }
    }

    private func setCachedImages(_ pairs: [(String, NSImage)]) {
        for (path, img) in pairs {
            cache[path] = img
            inFlight.remove(path)
        }
    }
}
