// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// AppKit owns tracking, keyboard input and accessibility; the cell only
/// draws the larger filled track used by the notch's level controls.
struct NotchLevelSlider: NSViewRepresentable {
    @Binding var value: Double
    let label: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSlider, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 180, height: proposal.height ?? 28)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        slider.cell = NotchLevelCell()
        slider.minValue = 0
        slider.maxValue = 1
        slider.isContinuous = true
        slider.altIncrementValue = 0.01
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.setAccessibilityLabel(label)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        let bounded = value.isFinite ? min(1, max(0, value)) : 0
        if slider.doubleValue != bounded { slider.doubleValue = bounded }
        slider.isEnabled = context.environment.isEnabled
        slider.setAccessibilityValueDescription("\(Int((bounded * 100).rounded()))%")
        slider.setAccessibilityLabel(label)
    }

    final class Coordinator: NSObject {
        var parent: NotchLevelSlider
        init(_ parent: NotchLevelSlider) { self.parent = parent }
        @objc func changed(_ sender: NSSlider) { parent.value = sender.doubleValue }
    }
}

private final class NotchLevelCell: NSSliderCell {
    override func barRect(flipped: Bool) -> NSRect {
        (controlView?.bounds ?? .zero).insetBy(dx: 1, dy: 3)
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = barRect(flipped: flipped)
        guard track.width > 0, track.height > 0 else { return }
        let outline = NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        NSColor.white.withAlphaComponent(0.13).setFill()
        track.fill()
        let fraction = maxValue > minValue ? min(1, max(0, (doubleValue - minValue) / (maxValue - minValue))) : 0
        NSColor.white.withAlphaComponent(isEnabled ? 0.92 : 0.3).setFill()
        NSRect(x: track.minX, y: track.minY, width: track.width * fraction, height: track.height).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func drawKnob(_ knobRect: NSRect) {}
}
