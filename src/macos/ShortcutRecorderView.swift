//
//  ShortcutRecorderView.swift
//  Arculator
//
//  A click-to-record key combo field. Wraps a custom NSView in a
//  SwiftUI NSViewRepresentable so it can sit in a SwiftUI Form row.
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {

    @Binding var combo: KeyCombo

    func makeCoordinator() -> Coordinator {
        Coordinator(combo: $combo)
    }

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.coordinator = context.coordinator
        view.combo = combo
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.coordinator = context.coordinator
        if nsView.combo != combo {
            nsView.combo = combo
        }
    }

    final class Coordinator {
        var binding: Binding<KeyCombo>
        init(combo: Binding<KeyCombo>) { self.binding = combo }
        func update(_ newCombo: KeyCombo) { binding.wrappedValue = newCombo }
    }
}

final class ShortcutRecorderNSView: NSView {

    weak var coordinator: ShortcutRecorderView.Coordinator?

    var combo: KeyCombo = .default {
        didSet { needsDisplay = true }
    }

    private var isRecording = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityIdentifier("releaseShortcutRecorder")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            isRecording = true
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            isRecording = false
        }
        return ok
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Cancel on Escape with no modifiers (preserves the existing combo).
        if Int(event.keyCode) == kVK_Escape
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isDisjoint(with: [.command, .control, .option, .shift])
        {
            window?.makeFirstResponder(nil)
            return
        }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .control, .option, .shift])

        let newCombo = KeyCombo(keyCode: Int(event.keyCode), modifierFlags: mods)
        combo = newCombo
        coordinator?.update(newCombo)
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let radius: CGFloat = 4
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: radius, yRadius: radius)

        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        } else {
            NSColor.controlBackgroundColor.setFill()
        }
        path.fill()

        if isRecording {
            NSColor.controlAccentColor.setStroke()
        } else {
            NSColor.separatorColor.setStroke()
        }
        path.lineWidth = 1
        path.stroke()

        let label = isRecording ? "Press a key combo…" : combo.displayString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: isRecording
                ? NSColor.secondaryLabelColor
                : NSColor.labelColor,
        ]
        let attributed = NSAttributedString(string: label, attributes: attrs)
        let size = attributed.size()
        let textRect = NSRect(
            x: (bounds.width  - size.width)  / 2,
            y: (bounds.height - size.height) / 2,
            width:  size.width,
            height: size.height
        )
        attributed.draw(in: textRect)
    }
}
