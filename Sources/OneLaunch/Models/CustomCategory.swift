import Foundation

struct CustomCategory: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var appIDs: [String]

    init(id: String = UUID().uuidString, name: String, appIDs: [String] = []) {
        self.id = id
        self.name = name
        self.appIDs = appIDs
    }
}
