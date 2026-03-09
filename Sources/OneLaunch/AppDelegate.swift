import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launcherPanelController = LauncherPanelController()
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var hotKeyService: HotKeyService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        configureStatusItem()
        configureHotKey()
        // 不自动打开界面，仅后台运行；用户通过快捷键 / 状态栏 / 菜单打开
        preloadIconsInBackground()
    }

    /// 启动时在后台预加载应用图标，首次打开面板时减少卡顿
    private func preloadIconsInBackground() {
        Task.detached(priority: .utility) {
            let list = AppScanner().loadCachedApplications()
            if let apps = list, !apps.isEmpty {
                await MainActor.run {
                    AppIconProvider.shared.preload(apps: apps, limit: 80)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if launcherPanelController.isVisible || flag {
            launcherPanelController.hide()
        } else {
            launcherPanelController.show()
        }

        return true
    }

    @objc private func showLauncher() {
        launcherPanelController.show()
    }

    @objc private func toggleLauncher() {
        launcherPanelController.toggle()
    }

    @objc private func handleStatusItemClick(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else {
            toggleLauncher()
            return
        }

        if event.type == .rightMouseUp {
            guard let statusItem, let statusMenu else {
                return
            }

            statusItem.popUpMenu(statusMenu)
            return
        }

        toggleLauncher()
    }

    @objc private func refreshApps() {
        launcherPanelController.viewModel.refreshApplications()
        launcherPanelController.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func configureHotKey() {
        hotKeyService = HotKeyService(
            keyCode: UInt32(kVK_Space),
            modifiers: [.option]
        ) { [weak self] in
            Task { @MainActor in
                self?.launcherPanelController.toggle()
            }
        }

        hotKeyService?.register()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "OneLaunch")
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(handleStatusItemClick(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开 OneLaunch", action: #selector(showLauncher), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "重新扫描应用", action: #selector(refreshApps), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        statusMenu = menu
        statusItem = item
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "打开 OneLaunch", action: #selector(showLauncher), keyEquivalent: "o"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出 OneLaunch", action: #selector(quitApp), keyEquivalent: "q"))

        appMenu.items.forEach { $0.target = self }
        appMenuItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
}
