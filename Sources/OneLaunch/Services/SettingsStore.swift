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

enum CategoryBarPosition: String, CaseIterable, Sendable {
    case left = "left"
    case right = "right"
    case bottom = "bottom"

    var displayName: String {
        switch self {
        case .left: return "左侧"
        case .right: return "右侧"
        case .bottom: return "下方"
        }
    }

    var icon: String {
        switch self {
        case .left: return "sidebar.left"
        case .right: return "sidebar.right"
        case .bottom: return "rectangle.bottomhalf.inset.filled"
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
        static let customCategories = "settings.customCategories"
        static let systemCategoryOverrides = "settings.systemCategoryOverrides"
        static let systemCategoryOrder = "settings.systemCategoryOrder"
        static let categoryBarPosition = "settings.categoryBarPosition"
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
            let clamped = min(36, max(0, backgroundBlurRadius))
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

    @Published var customCategories: [CustomCategory] {
        didSet {
            let normalized = Self.normalizeCustomCategories(customCategories)
            if normalized != customCategories {
                customCategories = normalized
                return
            }
            saveCustomCategories(customCategories)
        }
    }

    @Published var systemCategoryOverrides: [String: AppCategory] {
        didSet {
            let normalized = Self.normalizeSystemCategoryOverrides(systemCategoryOverrides)
            if normalized != systemCategoryOverrides {
                systemCategoryOverrides = normalized
                return
            }
            saveSystemCategoryOverrides(systemCategoryOverrides)
        }
    }

    @Published var systemCategoryOrder: [String] {
        didSet {
            let normalized = Self.normalizeSystemCategoryOrder(systemCategoryOrder)
            if normalized != systemCategoryOrder {
                systemCategoryOrder = normalized
                return
            }
            saveSystemCategoryOrder(systemCategoryOrder)
        }
    }

    @Published var categoryBarPosition: CategoryBarPosition {
        didSet {
            defaults.set(categoryBarPosition.rawValue, forKey: Key.categoryBarPosition)
        }
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
        self.backgroundBlurRadius = storedBlurRadius > 0 ? min(36, max(0, storedBlurRadius)) : 18
        self.manualAppOrder = defaults.stringArray(forKey: Key.manualAppOrder) ?? []
        self.appFolders = Self.loadFolders(from: defaults)
        self.customCategories = Self.loadCustomCategories(from: defaults)
        self.systemCategoryOverrides = Self.loadSystemCategoryOverrides(from: defaults)
        self.systemCategoryOrder = Self.loadSystemCategoryOrder(from: defaults)
        let storedCategoryBarPosition = defaults.string(forKey: Key.categoryBarPosition) ?? CategoryBarPosition.left.rawValue
        self.categoryBarPosition = CategoryBarPosition(rawValue: storedCategoryBarPosition) ?? .left
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
        customCategories = []
        systemCategoryOverrides = [:]
        systemCategoryOrder = Self.defaultSystemCategoryOrderRawValues()
        categoryBarPosition = .left
    }

    var orderedSystemCategories: [AppCategory] {
        let orderedRawValues = Self.normalizeSystemCategoryOrder(systemCategoryOrder)
        var seen = Set<AppCategory>([.all])
        var categories: [AppCategory] = [.all]

        for rawValue in orderedRawValues {
            guard let category = AppCategory(rawValue: rawValue), category != .all else { continue }
            guard seen.insert(category).inserted else { continue }
            categories.append(category)
        }

        for category in AppCategory.allCases where category != .all {
            if seen.insert(category).inserted {
                categories.append(category)
            }
        }

        return categories
    }

    func addCustomCategory(named name: String) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let duplicated = customCategories.contains {
            $0.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard !duplicated else { return nil }

        let category = CustomCategory(name: trimmedName)
        customCategories.append(category)
        return category.id
    }

    func renameCustomCategory(_ categoryID: String, to name: String) {
        guard let index = customCategories.firstIndex(where: { $0.id == categoryID }) else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let duplicated = customCategories.contains {
            $0.id != categoryID && $0.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard !duplicated else { return }

        customCategories[index].name = trimmedName
    }

    func deleteCustomCategory(_ categoryID: String) {
        customCategories.removeAll { $0.id == categoryID }
    }

    func moveCustomCategoryUp(_ categoryID: String) {
        guard let index = customCategories.firstIndex(where: { $0.id == categoryID }), index > 0 else {
            return
        }

        var categories = customCategories
        let category = categories.remove(at: index)
        categories.insert(category, at: index - 1)
        customCategories = categories
    }

    func moveCustomCategoryDown(_ categoryID: String) {
        guard let index = customCategories.firstIndex(where: { $0.id == categoryID }),
              index < customCategories.count - 1 else {
            return
        }

        var categories = customCategories
        let category = categories.remove(at: index)
        categories.insert(category, at: index + 1)
        customCategories = categories
    }

    func moveSystemCategoryUp(_ category: AppCategory) {
        guard category != .all else { return }

        var categories = orderedSystemCategories.filter { $0 != .all }
        guard let index = categories.firstIndex(of: category), index > 0 else {
            return
        }

        let moved = categories.remove(at: index)
        categories.insert(moved, at: index - 1)
        systemCategoryOrder = categories.map(\.rawValue)
    }

    func moveSystemCategoryDown(_ category: AppCategory) {
        guard category != .all else { return }

        var categories = orderedSystemCategories.filter { $0 != .all }
        guard let index = categories.firstIndex(of: category), index < categories.count - 1 else {
            return
        }

        let moved = categories.remove(at: index)
        categories.insert(moved, at: index + 1)
        systemCategoryOrder = categories.map(\.rawValue)
    }

    func isApp(_ appID: String, inCustomCategory categoryID: String) -> Bool {
        customCategories.first(where: { $0.id == categoryID })?.appIDs.contains(appID) == true
    }

    func assignApp(_ appID: String, toCustomCategory categoryID: String) {
        guard let targetIndex = customCategories.firstIndex(where: { $0.id == categoryID }) else {
            return
        }

        var categories = customCategories
        var didChange = false

        for index in categories.indices {
            let oldCount = categories[index].appIDs.count
            categories[index].appIDs.removeAll { $0 == appID }
            if categories[index].appIDs.count != oldCount {
                didChange = true
            }
        }

        if !categories[targetIndex].appIDs.contains(appID) {
            categories[targetIndex].appIDs.append(appID)
            didChange = true
        }

        if didChange {
            customCategories = categories
        }
    }

    func removeApp(_ appID: String, fromCustomCategory categoryID: String) {
        guard let index = customCategories.firstIndex(where: { $0.id == categoryID }) else {
            return
        }
        customCategories[index].appIDs.removeAll { $0 == appID }
    }

    func removeAppFromAllCustomCategories(_ appID: String) {
        var categories = customCategories
        var didChange = false

        for index in categories.indices {
            let oldCount = categories[index].appIDs.count
            categories[index].appIDs.removeAll { $0 == appID }
            if categories[index].appIDs.count != oldCount {
                didChange = true
            }
        }

        if didChange {
            customCategories = categories
        }
    }

    func systemCategoryOverride(for appID: String) -> AppCategory? {
        systemCategoryOverrides[appID]
    }

    func effectiveCategory(for app: AppItem) -> AppCategory {
        systemCategoryOverrides[app.id] ?? app.category
    }

    func setSystemCategoryOverride(appID: String, category: AppCategory?) {
        guard !appID.isEmpty else { return }

        if let category, category != .all {
            systemCategoryOverrides[appID] = category
        } else {
            systemCategoryOverrides.removeValue(forKey: appID)
        }
    }

    func clearSystemCategoryOverride(appID: String) {
        systemCategoryOverrides.removeValue(forKey: appID)
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

    private static func loadCustomCategories(from defaults: UserDefaults) -> [CustomCategory] {
        guard let data = defaults.data(forKey: Key.customCategories) else { return [] }
        let categories = (try? JSONDecoder().decode([CustomCategory].self, from: data)) ?? []
        return normalizeCustomCategories(categories)
    }

    private func saveCustomCategories(_ categories: [CustomCategory]) {
        if categories.isEmpty {
            defaults.removeObject(forKey: Key.customCategories)
            return
        }

        if let data = try? JSONEncoder().encode(categories) {
            defaults.set(data, forKey: Key.customCategories)
        }
    }

    private static func loadSystemCategoryOverrides(from defaults: UserDefaults) -> [String: AppCategory] {
        guard let data = defaults.data(forKey: Key.systemCategoryOverrides) else { return [:] }
        guard let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }

        var result: [String: AppCategory] = [:]
        for (appID, rawValue) in raw {
            guard let category = AppCategory(rawValue: rawValue), category != .all else {
                continue
            }
            result[appID] = category
        }

        return normalizeSystemCategoryOverrides(result)
    }

    private func saveSystemCategoryOverrides(_ overrides: [String: AppCategory]) {
        if overrides.isEmpty {
            defaults.removeObject(forKey: Key.systemCategoryOverrides)
            return
        }

        let raw = Dictionary(overrides.map { ($0.key, $0.value.rawValue) }, uniquingKeysWith: { _, latest in latest })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Key.systemCategoryOverrides)
        }
    }

    private static func loadSystemCategoryOrder(from defaults: UserDefaults) -> [String] {
        let stored = defaults.stringArray(forKey: Key.systemCategoryOrder) ?? []
        if stored.isEmpty {
            return defaultSystemCategoryOrderRawValues()
        }
        return normalizeSystemCategoryOrder(stored)
    }

    private func saveSystemCategoryOrder(_ order: [String]) {
        let normalized = Self.normalizeSystemCategoryOrder(order)
        if normalized.isEmpty {
            defaults.removeObject(forKey: Key.systemCategoryOrder)
        } else {
            defaults.set(normalized, forKey: Key.systemCategoryOrder)
        }
    }

    private static func normalizeCustomCategories(_ categories: [CustomCategory]) -> [CustomCategory] {
        var seenIDs = Set<String>()
        var seenAppIDsAcrossCategories = Set<String>()

        return categories.compactMap { category in
            let trimmedName = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return nil }
            guard seenIDs.insert(category.id).inserted else { return nil }

            var seenAppIDsInCategory = Set<String>()
            let dedupedAppIDs = category.appIDs.filter { appID in
                guard seenAppIDsInCategory.insert(appID).inserted else { return false }
                guard seenAppIDsAcrossCategories.insert(appID).inserted else { return false }
                return true
            }
            return CustomCategory(id: category.id, name: trimmedName, appIDs: dedupedAppIDs)
        }
    }

    private static func normalizeSystemCategoryOverrides(_ overrides: [String: AppCategory]) -> [String: AppCategory] {
        overrides.reduce(into: [:]) { partialResult, pair in
            let appID = pair.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !appID.isEmpty else { return }
            guard pair.value != .all else { return }
            partialResult[appID] = pair.value
        }
    }

    private static func normalizeSystemCategoryOrder(_ order: [String]) -> [String] {
        var seen = Set<String>()
        let validRawValues = Set(AppCategory.allCases.filter { $0 != .all }.map(\.rawValue))

        return order.compactMap { rawValue in
            guard validRawValues.contains(rawValue) else { return nil }
            guard seen.insert(rawValue).inserted else { return nil }
            return rawValue
        }
    }

    private static func defaultSystemCategoryOrderRawValues() -> [String] {
        AppCategory.allCases.filter { $0 != .all }.map(\.rawValue)
    }
}
