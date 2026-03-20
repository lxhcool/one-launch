import Foundation

enum AppCategory: String, CaseIterable, Identifiable {
    case all = "全部"
    case productivity = "效率"
    case developerTools = "开发"
    case graphicsDesign = "设计"
    case socialNetworking = "社交"
    case entertainment = "娱乐"
    case utilities = "工具"
    case education = "教育"
    case business = "商务"
    case other = "其他"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .productivity: return "checkmark.circle"
        case .developerTools: return "terminal"
        case .graphicsDesign: return "paintbrush"
        case .socialNetworking: return "person.2"
        case .entertainment: return "play.circle"
        case .utilities: return "wrench"
        case .education: return "book"
        case .business: return "briefcase"
        case .other: return "app"
        }
    }

    static func resolve(name: String, bundleIdentifier: String?, lsCategoryType: String?) -> AppCategory {
        if let lsCategoryType {
            switch lsCategoryType {
            case "public.app-category.developer-tools": return .developerTools
            case "public.app-category.productivity": return .productivity
            case "public.app-category.graphics-design", "public.app-category.photography": return .graphicsDesign
            case "public.app-category.social-networking": return .socialNetworking
            case "public.app-category.entertainment", "public.app-category.games": return .entertainment
            case "public.app-category.utilities": return .utilities
            case "public.app-category.education", "public.app-category.reference": return .education
            case "public.app-category.business", "public.app-category.finance": return .business
            default: break
            }
        }

        let source = "\(name.lowercased()) \(bundleIdentifier?.lowercased() ?? "")"

        if source.containsAny(["xcode", "cursor", "vscode", "terminal", "github", "iterm", "jetbrains", "postman", "docker", "insomnia", "dbngin"]) {
            return .developerTools
        }
        if source.containsAny(["figma", "photoshop", "illustrator", "sketch", "adobe", "affinity", "pixelmator", "canva"]) {
            return .graphicsDesign
        }
        if source.containsAny(["wechat", "qq", "telegram", "slack", "discord", "dingtalk", "feishu", "lark", "teams", "zoom"]) {
            return .socialNetworking
        }
        if source.containsAny(["music", "video", "spotify", "vlc", "bilibili", "youtube", "netflix", "steam", "game"]) {
            return .entertainment
        }
        if source.containsAny(["clean", "monitor", "sync", "backup", "zip", "unarchiver", "alfred", "raycast", "screenshot", "finder"]) {
            return .utilities
        }
        if source.containsAny(["notion", "notes", "todo", "calendar", "mail", "office", "word", "excel", "powerpoint"]) {
            return .productivity
        }
        if source.containsAny(["school", "class", "learn", "study", "course", "dictionary", "translate"]) {
            return .education
        }
        if source.containsAny(["business", "finance", "bank", "account", "invoice", "erp", "crm"] ) {
            return .business
        }

        return .other
    }
}

struct AppItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleIdentifier: String?
    let category: AppCategory

    var id: String {
        bundleIdentifier ?? url.path
    }

    init(url: URL, name: String, bundleIdentifier: String?, category: AppCategory? = nil) {
        self.url = url
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.category = category ?? AppCategory.resolve(name: name, bundleIdentifier: bundleIdentifier, lsCategoryType: nil)
    }
}

private extension String {
    func containsAny(_ keywords: [String]) -> Bool {
        keywords.contains(where: { self.contains($0) })
    }
}
