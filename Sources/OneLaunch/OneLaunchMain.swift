import AppKit

@main
@MainActor
struct OneLaunchMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()

        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
