import AppKit
import CoreImage
import Foundation
import ImageIO
import ServiceManagement
import UniformTypeIdentifiers

enum SortMode: String, CaseIterable, Sendable {
    case recent = "recent"
    case alpha = "alpha"
    case frequency = "frequency"
    case manual = "manual"

    var displayName: String {
        switch self {
        case .recent: "最近使用"
        case .alpha: "字母排序"
        case .frequency: "使用频率"
        case .manual: "手动排序"
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private let defaults: UserDefaults
    private var backgroundSelectionTask: Task<Void, Never>?

    private enum Key {
        static let iconSize = "settings.iconSize"
        static let listContentWidth = "settings.listContentWidth"
        static let sortMode = "settings.sortMode"
        static let backgroundImagePath = "settings.backgroundImagePath"
        static let backgroundBlurRadius = "settings.backgroundBlurRadius"
        static let manualAppOrder = "settings.manualAppOrder"
        static let appFolders = "settings.appFolders"
    }

    @Published var iconSize: Double {
        didSet { defaults.set(iconSize, forKey: Key.iconSize) }
    }

    @Published var listContentWidth: Double {
        didSet { defaults.set(listContentWidth, forKey: Key.listContentWidth) }
    }

    @Published var sortMode: SortMode {
        didSet { defaults.set(sortMode.rawValue, forKey: Key.sortMode) }
    }

    @Published var backgroundImagePath: String? {
        didSet {
            defaults.set(backgroundImagePath, forKey: Key.backgroundImagePath)
            reloadBackgroundImage()
        }
    }

    @Published var backgroundBlurRadius: Double {
        didSet {
            let clamped = min(36, max(8, backgroundBlurRadius))
            if clamped != backgroundBlurRadius {
                backgroundBlurRadius = clamped
                return
            }

            defaults.set(backgroundBlurRadius, forKey: Key.backgroundBlurRadius)
            if backgroundImagePath != nil {
                reloadBackgroundImage()
            }
        }
    }

    @Published private(set) var backgroundImage: NSImage?
    @Published private(set) var backgroundBlurImage: NSImage?
    @Published private(set) var backgroundIsDark = true

    @Published var manualAppOrder: [String] {
        didSet { defaults.set(manualAppOrder, forKey: Key.manualAppOrder) }
    }

    @Published var appFolders: [AppFolder] {
        didSet { saveFolders(appFolders) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            if launchAtLogin {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedIconSize = defaults.double(forKey: Key.iconSize)
        self.iconSize = storedIconSize > 0 ? storedIconSize : 76

        let storedContentWidth = defaults.double(forKey: Key.listContentWidth)
        self.listContentWidth = storedContentWidth > 0 ? storedContentWidth : 1460

        let storedSort = defaults.string(forKey: Key.sortMode) ?? SortMode.recent.rawValue
        self.sortMode = SortMode(rawValue: storedSort) ?? .recent

        self.backgroundImagePath = defaults.string(forKey: Key.backgroundImagePath)
        let storedBlurRadius = defaults.double(forKey: Key.backgroundBlurRadius)
        self.backgroundBlurRadius = storedBlurRadius > 0 ? min(36, max(8, storedBlurRadius)) : 18
        self.manualAppOrder = defaults.stringArray(forKey: Key.manualAppOrder) ?? []
        self.appFolders = Self.loadFolders(from: defaults)
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        reloadBackgroundImage()

        // 稳定策略：仅使用 OneLaunch 自己维护的文件夹。
        // 如果历史版本曾生成“自动文件夹”，这里直接清理掉，避免继续影响布局。
        if appFolders.contains(where: { $0.isAuto }) {
            appFolders.removeAll { $0.isAuto }
        }
    }

    func resetToDefaults() {
        iconSize = 76
        listContentWidth = 1460
        sortMode = .recent
        backgroundBlurRadius = 18
        clearBackgroundImage()
        manualAppOrder = []
        appFolders = []
    }

    func setBackgroundImage(from sourceURL: URL) {
        let sourcePath = sourceURL.path
        let previousPath = backgroundImagePath
        let screenSize = NSScreen.main?.frame.size ?? NSSize(width: 1920, height: 1080)
        let screenScale = min(NSScreen.main?.backingScaleFactor ?? 2, 1.5)

        backgroundSelectionTask?.cancel()
        backgroundSelectionTask = Task { @MainActor in
            let compressedPath = await Task.detached(priority: .userInitiated) {
                Self.compressAndPersistBackgroundImage(
                    sourcePath: sourcePath,
                    screenSize: screenSize,
                    screenScale: screenScale,
                    maxBytes: 1_000_000
                )
            }.value

            guard !Task.isCancelled else { return }

            if let compressedPath {
                deleteManagedBackgroundIfNeeded(at: previousPath)
                backgroundImagePath = compressedPath
            } else {
                NSSound.beep()
                NSLog("Failed to compress background image under 1MB; keeping previous background.")
            }
        }
    }

    func clearBackgroundImage() {
        let oldPath = backgroundImagePath
        backgroundImagePath = nil
        deleteManagedBackgroundIfNeeded(at: oldPath)
    }

    private func reloadBackgroundImage() {
        guard let path = backgroundImagePath else {
            backgroundImage = nil
            backgroundBlurImage = nil
            backgroundIsDark = true
            return
        }

        let screenSize = NSScreen.main?.frame.size ?? NSSize(width: 1920, height: 1080)
        let screenScale = min(NSScreen.main?.backingScaleFactor ?? 2, 1.5)
        if let rendered = Self.loadOptimizedBackgroundImages(
            atPath: path,
            screenSize: screenSize,
            screenScale: screenScale,
            blurRadius: backgroundBlurRadius
        ) {
            backgroundImage = rendered.base
            backgroundBlurImage = rendered.blur
            backgroundIsDark = rendered.isDark
            return
        }

        backgroundImage = NSImage(contentsOfFile: path)
        backgroundBlurImage = nil
        if let cgImage = backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            backgroundIsDark = Self.isImageDark(cgImage: cgImage)
        } else {
            backgroundIsDark = true
        }
    }

    nonisolated private static let backgroundCIContext = CIContext(options: [
        .cacheIntermediates: true
    ])

    nonisolated private static func loadOptimizedBackgroundImages(
        atPath path: String,
        screenSize: NSSize,
        screenScale: CGFloat,
        blurRadius: Double
    ) -> (base: NSImage, blur: NSImage?, isDark: Bool)? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let fileSizeInBytes: UInt64 = {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attrs[.size] as? NSNumber else {
                return 0
            }
            return size.uint64Value
        }()

        let longestSide = max(screenSize.width, screenSize.height) * screenScale
        let cappedByScreen = Int(min(1800, max(1100, longestSide)))
        let maxPixelSize: Int
        if fileSizeInBytes >= 8 * 1024 * 1024 {
            // 对超大图片强制更激进降采样，避免拖拽时 GPU 纹理过大导致卡顿。
            maxPixelSize = min(cappedByScreen, 1280)
        } else {
            maxPixelSize = cappedByScreen
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldCache: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let base = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let blur = makeGaussianBlurredImage(from: cgImage, radius: CGFloat(blurRadius))
        let isDark = isImageDark(cgImage: cgImage)
        return (base: base, blur: blur, isDark: isDark)
    }

    nonisolated private static func makeGaussianBlurredImage(from cgImage: CGImage, radius: CGFloat) -> NSImage? {
        let input = CIImage(cgImage: cgImage)
        let blurred = input
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: input.extent)
            .applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputSaturationKey: 1.04,
                    kCIInputBrightnessKey: -0.02
                ]
            )

        guard let outputCG = backgroundCIContext.createCGImage(blurred, from: input.extent) else {
            return nil
        }

        return NSImage(cgImage: outputCG, size: NSSize(width: outputCG.width, height: outputCG.height))
    }

    nonisolated private static func isImageDark(cgImage: CGImage) -> Bool {
        let input = CIImage(cgImage: cgImage)
        let extent = input.extent
        guard !extent.isEmpty else { return true }

        let average = input.applyingFilter(
            "CIAreaAverage",
            parameters: [kCIInputExtentKey: CIVector(cgRect: extent)]
        )

        var pixel = [UInt8](repeating: 0, count: 4)
        backgroundCIContext.render(
            average,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let r = Double(pixel[0]) / 255.0
        let g = Double(pixel[1]) / 255.0
        let b = Double(pixel[2]) / 255.0
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance < 0.55
    }

    private func deleteManagedBackgroundIfNeeded(at path: String?) {
        guard let path else { return }
        let managedPrefix = Self.managedBackgroundDirectoryURL().path + "/"
        guard path.hasPrefix(managedPrefix) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    nonisolated private static func compressAndPersistBackgroundImage(
        sourcePath: String,
        screenSize: NSSize,
        screenScale: CGFloat,
        maxBytes: Int
    ) -> String? {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            return nil
        }

        let longestSide = max(screenSize.width, screenSize.height) * screenScale
        let candidatePixels: [Int] = [
            Int(min(1600, max(1200, longestSide))),
            1400,
            1200,
            1000,
            900,
            768,
            640,
            512
        ]

        for maxPixel in candidatePixels {
            guard let cgImage = makeThumbnail(from: source, maxPixelSize: maxPixel) else { continue }
            guard let jpegData = makeCompressedJPEGData(from: cgImage, maxBytes: maxBytes) else { continue }
            if let filePath = persistManagedBackground(data: jpegData) {
                return filePath
            }
        }

        return nil
    }

    nonisolated private static func makeThumbnail(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldCache: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    nonisolated private static func makeCompressedJPEGData(from cgImage: CGImage, maxBytes: Int) -> Data? {
        let qualities: [CGFloat] = [0.78, 0.68, 0.58, 0.50, 0.42, 0.34, 0.28]

        for quality in qualities {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else { continue }

            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: quality,
                kCGImageDestinationOptimizeColorForSharing: true
            ]
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

            guard CGImageDestinationFinalize(destination) else { continue }
            if data.length <= maxBytes {
                return data as Data
            }
        }

        return nil
    }

    nonisolated private static func persistManagedBackground(data: Data) -> String? {
        let dir = managedBackgroundDirectoryURL()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let filename = "bg-\(UUID().uuidString).jpg"
            let targetURL = dir.appendingPathComponent(filename)
            try data.write(to: targetURL, options: .atomic)
            return targetURL.path
        } catch {
            return nil
        }
    }

    nonisolated private static func managedBackgroundDirectoryURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return appSupport
            .appendingPathComponent("OneLaunch", isDirectory: true)
            .appendingPathComponent("Backgrounds", isDirectory: true)
    }

    private static func loadFolders(from defaults: UserDefaults) -> [AppFolder] {
        guard let data = defaults.data(forKey: Key.appFolders) else { return [] }
        return (try? JSONDecoder().decode([AppFolder].self, from: data)) ?? []
    }

    private func saveFolders(_ folders: [AppFolder]) {
        if folders.isEmpty {
            defaults.removeObject(forKey: Key.appFolders)
            return
        }

        if let data = try? JSONEncoder().encode(folders) {
            defaults.set(data, forKey: Key.appFolders)
        }
    }
}
