import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class LauncherPanelController: NSObject {
    let viewModel = LauncherViewModel()
    private var lastScreenFrame: NSRect?
    private var hasPrewarmed = false
    private var isAnimating = false

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
        panel.animationBehavior = .none
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
        guard !isAnimating else { return }

        if let targetScreen = currentScreen() {
            let frame = targetScreen.frame
            if lastScreenFrame != frame {
                panel.setFrame(frame, display: false)
                lastScreenFrame = frame
            }
        }

        isAnimating = true

        // 初始状态：半透明 + 轻微缩小
        panel.alphaValue = 0
        panel.contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.92, y: 0.92))

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.contentView?.layer?.setAffineTransform(.identity)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.isAnimating = false
            }
        })

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
        guard panel.isVisible, !isAnimating else {
            return
        }

        isAnimating = true
        viewModel.isPresented = false
        
        // 清空搜索
        viewModel.clearSearch()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.96, y: 0.96))
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.panel.orderOut(nil)
                self?.panel.alphaValue = 1
                self?.panel.contentView?.layer?.setAffineTransform(.identity)
                self?.isAnimating = false
            }
        })
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
