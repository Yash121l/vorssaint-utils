// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A bounded command shared by the UI process and its playback adapter.
enum NotchPlaybackCommand: Equatable {
    case toggle, next, previous
    case seek(Double)

    init?(message: String) {
        switch message {
        case "toggle": self = .toggle
        case "next": self = .next
        case "previous": self = .previous
        default:
            guard message.hasPrefix("seek "),
                  let position = Double(message.dropFirst(5)), Self.validPosition(position) else { return nil }
            self = .seek(position)
        }
    }

    var message: String? {
        switch self {
        case .toggle: return "toggle"
        case .next: return "next"
        case .previous: return "previous"
        case .seek(let position): return Self.validPosition(position) ? "seek \(position)" : nil
        }
    }

    private static func validPosition(_ value: Double) -> Bool {
        value.isFinite && (0...604_800).contains(value)
    }
}
