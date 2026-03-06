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
}
