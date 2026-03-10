import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class LauncherPanelController: NSObject {
    let viewModel = LauncherViewModel()
    private var lastScreenFrame: NSRect?
    private var hasPrewarmed = false

    var isVisible: Bool {
        panel.isVisible
    }

    private lazy var panel: LauncherPanel = {
        let panel = LauncherPanel(
            contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .default
        panel.setFrameAutosaveName("OneLaunchPanel")

        let rootView = LauncherView(viewModel: viewModel, settingsStore: viewModel.settingsStore) { [weak self] in
            self?.hide()
        }

        panel.contentView = NSHostingView(rootView: rootView)
        return panel
    }()

    override init() {
        super.init()
        observeAppState()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        if let targetScreen = currentScreen() {
            let frame = targetScreen.frame
            if lastScreenFrame != frame {
                panel.setFrame(frame, display: false)
                lastScreenFrame = frame
            }
        }

        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        viewModel.isPresented = true
        viewModel.deferredPrepare()
    }

    func prewarmIfNeeded() {
        guard !hasPrewarmed else { return }
        hasPrewarmed = true

        if let targetScreen = currentScreen() {
            let frame = targetScreen.frame
            if lastScreenFrame != frame {
                panel.setFrame(frame, display: false)
                lastScreenFrame = frame
            }
        }

        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderFront(nil)
        panel.displayIfNeeded()
        panel.orderOut(nil)
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
    }

    func hide() {
        guard panel.isVisible else {
            return
        }
        viewModel.isPresented = false
        panel.orderOut(nil)
    }

    private func currentScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation

        return NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main
    }

    private func observeAppState() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidResignActive(_:)),
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )
    }

    @objc private func handleDidResignActive(_ notification: Notification) {
        hide()
    }
}
