// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Feedback is local to a visible control. No recurring work is needed.
struct NotchButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 10
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(enabled && hovered ? 0.07 : 0))
                    .allowsHitTesting(false)
            }
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.16), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: hovered)
            .onHover { hovered = $0 }
    }
}

struct NotchIconButton: View {
    let symbol: String
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? .white : .white.opacity(0.55))
                .frame(width: 28, height: 28)
                .background(.white.opacity(selected ? 0.1 : 0),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 9))
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct NotchEmptyView: View {
    let symbol: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 64, height: 64)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 250)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

struct NotchArtwork: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Color.black.overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.3, weight: .light))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

/// Short rows spread their remaining items evenly instead of leaving a hole.
struct NotchTileGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let columns: Int
    var spacing: CGFloat = 12
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(Array(stride(from: 0, to: items.count, by: max(1, columns))), id: \.self) { start in
                HStack(spacing: spacing) {
                    ForEach(Array(items[start..<min(items.count, start + max(1, columns))])) { item in
                        content(item).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

/// The base remains opaque black. Optional glass belongs to controls alone.
struct NotchControlSurface: ViewModifier {
    let cornerRadius: CGFloat
    var selected = false
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var glass = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
#if compiler(>=6.2)
            if #available(macOS 26, *), glass, !reduceTransparency {
                content.background(.black, in: shape)
                    .glassEffect(.regular.tint(.black.opacity(0.45)).interactive(), in: shape)
            } else {
                content.background(.white.opacity(selected ? 0.12 : 0.065), in: shape)
            }
#else
            content.background(.white.opacity(selected ? 0.12 : 0.065), in: shape)
#endif
        }
        .overlay {
            shape.strokeBorder(.white.opacity(contrast == .increased ? 0.5 : 0), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }
}
