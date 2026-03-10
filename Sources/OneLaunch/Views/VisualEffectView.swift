import AppKit
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> OptimizedVisualEffectView {
        let view = OptimizedVisualEffectView()
        view.apply(material: material, blendingMode: blendingMode)
        return view
    }

    func updateNSView(_ nsView: OptimizedVisualEffectView, context: Context) {
        nsView.apply(material: material, blendingMode: blendingMode)
    }
}

final class OptimizedVisualEffectView: NSVisualEffectView {
    func apply(material: NSVisualEffectView.Material, blendingMode: NSVisualEffectView.BlendingMode) {
        if state != .followsWindowActiveState {
            state = .followsWindowActiveState
        }
        if self.material != material {
            self.material = material
        }
        if self.blendingMode != blendingMode {
            self.blendingMode = blendingMode
        }
    }
}
