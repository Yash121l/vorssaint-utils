// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchTimerMode: String, CaseIterable { case timer, pomodoro }
enum NotchTimerPhase: String { case timer, focus, shortBreak, longBreak }

enum NotchTimerRulerScale {
    static let spacing = 14.0

    static func moving(_ value: Double, by points: Double) -> Double {
        guard value.isFinite, points.isFinite else { return 1 }
        return min(180, max(1, value - points / spacing))
    }

    static func minute(_ value: Double) -> Int {
        Int(moving(value, by: 0).rounded())
    }

    static func offset(of minute: Int, selected: Int) -> Double {
        (Double(minute) - Double(selected)) * spacing
    }
}

/// The deadline uses an injected, continuous time coordinate. UI refreshes and
/// delayed callbacks never subtract ticks, so sleep and busy frames cannot drift.
struct NotchTimerSession: Equatable {
    private(set) var mode: NotchTimerMode = .timer
    private(set) var phase: NotchTimerPhase = .timer
    private(set) var duration: TimeInterval = 300
    private(set) var deadline: TimeInterval?
    private(set) var pausedRemaining: TimeInterval?
    private(set) var completed = false
    private(set) var completedFocuses = 0

    var isRunning: Bool { deadline != nil }
    var isPaused: Bool { pausedRemaining != nil }
    var hasSession: Bool { isRunning || isPaused || completed }

    func remaining(at now: TimeInterval) -> TimeInterval {
        if let deadline { return max(0, deadline - now) }
        return pausedRemaining ?? (completed ? 0 : duration)
    }

    mutating func start(mode: NotchTimerMode, minutes: Int, now: TimeInterval) {
        guard !hasSession, now.isFinite else { return }
        self.mode = mode
        phase = mode == .pomodoro ? .focus : .timer
        duration = mode == .pomodoro ? 25 * 60 : Double(min(180, max(1, minutes))) * 60
        completedFocuses = 0
        deadline = now + duration
    }

    @discardableResult mutating func finishIfDue(at now: TimeInterval) -> Bool {
        guard let deadline, now.isFinite, now >= deadline else { return false }
        self.deadline = nil
        pausedRemaining = nil
        completed = true
        if phase == .focus { completedFocuses += 1 }
        return true
    }

    mutating func pause(at now: TimeInterval) {
        guard isRunning, now.isFinite else { return }
        if finishIfDue(at: now) { return }
        pausedRemaining = remaining(at: now)
        deadline = nil
    }

    mutating func resume(at now: TimeInterval) {
        guard let remaining = pausedRemaining, now.isFinite else { return }
        pausedRemaining = nil
        deadline = now + remaining
    }

    var nextPhase: NotchTimerPhase {
        phase == .focus ? (completedFocuses.isMultiple(of: 4) ? .longBreak : .shortBreak) : .focus
    }

    /// A new phase always starts by an explicit action. Returning from a long
    /// sleep cannot silently complete work/break cycles the user never took.
    mutating func startNext(at now: TimeInterval) {
        guard mode == .pomodoro, completed, now.isFinite else { return }
        phase = nextPhase
        duration = phase == .focus ? 25 * 60 : phase == .longBreak ? 15 * 60 : 5 * 60
        completed = false
        deadline = now + duration
    }

    mutating func cancel() { self = Self() }
}

enum NotchTimerSupport {
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchTimer.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchTimerEnabled)
            && NotchSupport.modules(in: defaults).contains(.timer)
    }

    static func clockText(_ remaining: TimeInterval) -> String {
        let seconds = remaining.isFinite ? Int(ceil(min(180 * 60, max(0, remaining)))) : 0
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func compactText(_ remaining: TimeInterval, locale: Locale) -> String {
        let seconds = remaining.isFinite ? ceil(min(180 * 60, max(0, remaining))) : 0
        return Duration.seconds(seconds).formatted(.units(
            allowed: [seconds >= 60 ? .minutes : .seconds], width: .narrow,
            fractionalPart: .hide(rounded: .down)).locale(locale))
    }
}
