// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchTimerView: View {
    @ObservedObject private var service = NotchTimerService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var mode: NotchTimerMode = .timer
    @State private var minutes = 15
    private var text: NotchActivityStrings { FeatureStrings.notchActivities(l10n.language) }

    var body: some View {
        ScrollView {
            Group {
                if service.session.hasSession { activeTimer }
                else { setup }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
        .tint(.orange)
    }

    private var setup: some View {
        VStack(spacing: 12) {
            Picker(text.timer, selection: $mode) {
                Text(text.timer).tag(NotchTimerMode.timer)
                Text(text.pomodoro).tag(NotchTimerMode.pomodoro)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
            if mode == .timer {
                NotchTimerRuler(minutes: $minutes, label: text.minutes)
                    .frame(height: 82)
            } else {
                Text(text.pomodoroHint)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 82)
            }
            HStack(spacing: 16) {
                Button { service.start(mode: mode, minutes: minutes) } label: {
                    Text(text.start)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .padding(.horizontal, 22).frame(height: 44)
                        .foregroundStyle(.orange)
                        .background(.orange.opacity(0.18), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: 22))
                Spacer(minLength: 0)
                clock(NotchTimerSupport.clockText(Double(mode == .timer ? minutes : 25) * 60))
            }
            .frame(height: 72)
        }
    }

    private var activeTimer: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                if !service.session.completed {
                    roundButton(symbol: service.session.isPaused ? "play.fill" : "pause.fill",
                                title: service.session.isPaused ? text.resume : l10n.s.actionPause,
                                primary: true, action: service.pauseOrResume)
                } else if service.session.mode == .pomodoro {
                    roundButton(symbol: "play.fill", title: text.start + " " + text.phase(service.session.nextPhase),
                                primary: true, action: service.startNext)
                }
                roundButton(symbol: "xmark",
                            title: service.session.completed ? l10n.s.supportIntroDoneButton : l10n.s.mediaCancel,
                            primary: false, action: service.cancel)
            }
            Spacer(minLength: 0)
            TimelineView(.animation(minimumInterval: 1, paused: !service.session.isRunning)) { _ in
                let remaining = NotchTimerSupport.clockText(service.session.remaining(at: service.now))
                let title = service.session.completed ? text.finished : text.phase(service.session.phase)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title).font(.system(size: 17, weight: .medium))
                        clock(remaining)
                    }.fixedSize()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(title).font(.system(size: 13, weight: .medium))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        clock(remaining)
                    }
                }
                .foregroundStyle(.orange)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(remaining)
            }
        }
        .frame(height: 96)
    }

    private func clock(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 62, weight: .thin)).monospacedDigit()
            .foregroundStyle(.orange)
            .lineLimit(1).minimumScaleFactor(0.5)
    }

    private func roundButton(symbol: String, title: String, primary: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(primary ? .orange : .white)
                .frame(width: 52, height: 52)
                .background(primary ? Color.orange.opacity(0.28) : Color.white.opacity(0.18), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 26))
        .accessibilityLabel(title)
        .help(title)
    }
}
