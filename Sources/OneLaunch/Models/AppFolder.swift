import Foundation

struct AppFolder: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var appIDs: [String]
    var isAuto: Bool
    var autoKey: String?

    init(id: String, name: String, appIDs: [String], isAuto: Bool = false, autoKey: String? = nil) {
        self.id = id
        self.name = name
        self.appIDs = appIDs
        self.isAuto = isAuto
        self.autoKey = autoKey
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, appIDs, isAuto, autoKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        appIDs = try container.decode([String].self, forKey: .appIDs)
        isAuto = (try? container.decode(Bool.self, forKey: .isAuto)) ?? false
        autoKey = try? container.decode(String.self, forKey: .autoKey)
    }
}
