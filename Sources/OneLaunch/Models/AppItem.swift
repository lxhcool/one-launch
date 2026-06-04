import Foundation

struct AppItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleIdentifier: String?

    var id: String {
        bundleIdentifier ?? url.path
    }

    init(url: URL, name: String, bundleIdentifier: String?) {
        self.url = url
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }
}
