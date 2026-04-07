//
//  EmulatorMetalView.swift
//  Arculator
//
//  NSViewRepresentable wrapping ArcMetalView (the existing MTKView subclass)
//  for embedding in SwiftUI view hierarchies.
//

import SwiftUI
import MetalKit

extension ArcMetalView {
    static func configuredView(frame: NSRect) -> ArcMetalView {
        let view = ArcMetalView(frame: frame, device: nil)
        view.autoresizingMask = [.width, .height]
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return view
    }
}

struct EmulatorMetalView: NSViewRepresentable {

    func makeNSView(context: Context) -> ArcMetalView {
        let view = ArcMetalView.configuredView(frame: .zero)
        EmulatorBridge.setVideoView(view)
        return view
    }

    func updateNSView(_ nsView: ArcMetalView, context: Context) {
        // The C renderer manages the view directly; no SwiftUI-driven updates needed.
    }
}
