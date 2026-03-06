import Foundation

struct AppItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleIdentifier: String?

    var id: String {
        bundleIdentifier ?? url.path
    }
}
