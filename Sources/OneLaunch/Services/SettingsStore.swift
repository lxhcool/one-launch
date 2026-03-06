import AppKit
import Foundation

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
        static let sortMode = "settings.sortMode"
        static let backgroundImagePath = "settings.backgroundImagePath"
        static let manualAppOrder = "settings.manualAppOrder"
    }

    @Published var iconSize: Double {
        didSet { defaults.set(iconSize, forKey: Key.iconSize) }
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedIconSize = defaults.double(forKey: Key.iconSize)
        self.iconSize = storedIconSize > 0 ? storedIconSize : 68

        let storedSort = defaults.string(forKey: Key.sortMode) ?? SortMode.recent.rawValue
        self.sortMode = SortMode(rawValue: storedSort) ?? .recent

        self.backgroundImagePath = defaults.string(forKey: Key.backgroundImagePath)
        self.manualAppOrder = defaults.stringArray(forKey: Key.manualAppOrder) ?? []
        reloadBackgroundImage()
    }

    func resetToDefaults() {
        iconSize = 68
        sortMode = .recent
        backgroundImagePath = nil
        manualAppOrder = []
    }

    private func reloadBackgroundImage() {
        if let path = backgroundImagePath {
            backgroundImage = NSImage(contentsOfFile: path)
        } else {
            backgroundImage = nil
        }
    }
}
