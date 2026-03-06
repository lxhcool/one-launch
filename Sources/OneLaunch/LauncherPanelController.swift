import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class LauncherPanelController: NSObject {
    let viewModel = LauncherViewModel()
    private var hideWorkItem: DispatchWorkItem?

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

        let rootView = LauncherView(viewModel: viewModel) { [weak self] in
            self?.hide()
        }

        panel.contentView = NSHostingView(rootView: rootView)
        return panel
    }()

    override init() {
        super.init()
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        if let targetScreen = currentScreen() {
            panel.setFrame(targetScreen.frame, display: false)
        }

        panel.alphaValue = 1
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        withAnimation(.snappy(duration: 0.38)) {
            viewModel.isPresented = true
        }

        viewModel.deferredPrepare()
    }

    func hide() {
        guard panel.isVisible else {
            return
        }

        hideWorkItem?.cancel()

        withAnimation(.easeOut(duration: 0.3)) {
            viewModel.isPresented = false
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
        }

        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func currentScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation

        return NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main
    }
}
