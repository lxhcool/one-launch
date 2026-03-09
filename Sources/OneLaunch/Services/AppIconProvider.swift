import AppKit

@MainActor
final class AppIconProvider {
    static let shared = AppIconProvider()

    private let cache = NSCache<NSString, NSImage>()

    private init() {}

    func icon(for app: AppItem) -> NSImage {
        let key = app.url.path as NSString

        if let cachedImage = cache.object(forKey: key) {
            return cachedImage
        }

        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        image.size = NSSize(width: 64, height: 64)
        cache.setObject(image, forKey: key)
        return image
    }

    /// 在后台预加载前 N 个应用图标，减轻首次打开列表时的卡顿
    func preload(apps: [AppItem], limit: Int = 80) {
        let toLoad = Array(apps.prefix(limit))
        guard !toLoad.isEmpty else { return }

        Task.detached(priority: .utility) {
            let loaded: [(String, NSImage)] = toLoad.compactMap { app in
                let path = app.url.path
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
            cache.setObject(img, forKey: path as NSString)
        }
    }
}
