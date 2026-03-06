import AppKit
import SwiftUI

struct ScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollBarHidingView {
        ScrollBarHidingView()
    }

    func updateNSView(_ nsView: ScrollBarHidingView, context: Context) {}
}

final class ScrollBarHidingView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.configureScrollView()
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        DispatchQueue.main.async { [weak self] in
            self?.configureScrollView()
        }
    }

    override func layout() {
        super.layout()
        configureScrollView()
    }

    private func configureScrollView() {
        guard let scrollView = findScrollView() else { return }

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false

        if !(scrollView.verticalScroller is InvisibleScroller) {
            scrollView.verticalScroller = InvisibleScroller()
        }
        if !(scrollView.horizontalScroller is InvisibleScroller) {
            scrollView.horizontalScroller = InvisibleScroller()
        }
    }

    private func findScrollView() -> NSScrollView? {
        var current: NSView? = self
        while let view = current {
            if let sv = view as? NSScrollView { return sv }
            current = view.superview
        }
        return nil
    }
}

private class InvisibleScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(
        for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style
    ) -> CGFloat { 0 }

    override func draw(_ dirtyRect: NSRect) {}
    override func drawKnob() {}
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
}
