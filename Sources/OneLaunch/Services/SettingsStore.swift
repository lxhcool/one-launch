import AppKit
import Foundation
import ServiceManagement

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

    private enum Key {
        static let iconSize = "settings.iconSize"
        static let listContentWidth = "settings.listContentWidth"
        static let sortMode = "settings.sortMode"
        static let backgroundImagePath = "settings.backgroundImagePath"
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

    @Published private(set) var backgroundImage: NSImage?

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
        backgroundImagePath = nil
        manualAppOrder = []
        appFolders = []
    }

    private func reloadBackgroundImage() {
        if let path = backgroundImagePath {
            backgroundImage = NSImage(contentsOfFile: path)
        } else {
            backgroundImage = nil
        }
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
