// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchMusicView: View {
    var compact = true
    @ObservedObject private var service = NotchMusicService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }

    var body: some View {
        VStack(spacing: 12) {
            if let playback = service.playback {
                ViewThatFits(in: .vertical) {
                    player(playback).fixedSize(horizontal: false, vertical: true)
                    ScrollView { player(playback).fixedSize(horizontal: false, vertical: true) }
                        .scrollIndicators(.automatic)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                HStack(spacing: 20) {
                    Image(systemName: "music.note")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 76, height: 76)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(text.mediaNothingPlaying).font(.system(size: 17, weight: .semibold))
                        Text(FeatureStrings.notch(l10n.language).musicHint)
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 84)
                .accessibilityElement(children: .combine)
            }
            if AppFeature.mixer.isAvailable { NotchAudioControls(inline: true) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func player(_ playback: NotchPlayback) -> some View {
        HStack(spacing: compact ? 18 : 24) {
            Button { RadialNowPlayingApplication.open(playback.track) } label: {
                NotchArtwork(image: service.artwork, size: compact ? 112 : 140)
                    .scaleEffect(playback.isPlaying || reduceMotion ? 1 : 0.94)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: playback.isPlaying)
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 24))
            .help(text.mediaNowPlaying)
            .accessibilityLabel(text.mediaNowPlaying)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(playback.track.title ?? text.mediaNowPlaying)
                        .font(.system(size: compact ? 18 : 21, weight: .semibold))
                        .lineLimit(2).help(playback.track.title ?? text.mediaNowPlaying)
                    Text(service.commandFailed ? l10n.s.monitorUnavailable : playback.track.artist ?? playback.track.album ?? text.mediaNowPlaying)
                        .font(.system(size: 13))
                        .foregroundStyle(service.commandFailed ? .orange : .secondary)
                        .lineLimit(1)
                }
                NotchMusicTimeline(playback: playback, service: service)
                transport(playback).frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 164)
    }

    private func transport(_ playback: NotchPlayback) -> some View {
        HStack(spacing: 22) {
            playbackButton("backward.end.fill", title: text.mediaPrevious, command: .previous)
            Button { service.send(.toggle) } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 20))
            .keyboardShortcut(.space, modifiers: [])
            .accessibilityLabel(text.mediaPlayPause)
            .help(text.mediaPlayPause)
            playbackButton("forward.end.fill", title: text.mediaNext, command: .next)
        }
        .frame(height: 44)
    }

    private func playbackButton(_ symbol: String, title: String, command: NotchMusicService.Command) -> some View {
        Button { service.send(command) } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 32, height: 36)
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(NotchButtonStyle())
        .accessibilityLabel(title)
        .help(title)
    }
}

private struct NotchMusicTimeline: View {
    let playback: NotchPlayback
    let service: NotchMusicService
    @ObservedObject private var l10n = L10n.shared
    @State private var scrubPosition: Double?
    @State private var scrubTrack: RadialNowPlayingSnapshot?
    @State private var pendingSeek: UUID?

    var body: some View {
        if playback.duration > 0 {
            TimelineView(.animation(minimumInterval: 1, paused: !playback.isPlaying)) { context in
                let position = scrubPosition ?? playback.position(at: context.date)
                VStack(spacing: 2) {
                    if playback.canSeek {
                        Slider(value: Binding(get: { position }, set: {
                            if scrubTrack == nil { scrubTrack = playback.track }
                            scrubPosition = $0
                        }), in: 0...playback.duration, onEditingChanged: { editing in
                            if editing {
                                pendingSeek = nil
                            } else if let scrubPosition, let scrubTrack {
                                service.seek(to: scrubPosition, in: scrubTrack)
                                pendingSeek = UUID()
                            }
                        })
                        .controlSize(.mini)
                        .accessibilityLabel(FeatureStrings.notch(l10n.language).playbackPosition)
                        .accessibilityValue(timestamp(position))
                    } else {
                        ProgressView(value: position, total: playback.duration)
                            .progressViewStyle(.linear).tint(.white.opacity(0.7))
                    }
                    HStack {
                        Text(timestamp(position))
                        Spacer()
                        Text("−" + timestamp(playback.duration - position))
                    }
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }
            .frame(height: 30)
            .onChange(of: playback.track) { clearScrub() }
            .onChange(of: playback.sampledAt) {
                if pendingSeek != nil, let scrubPosition,
                   abs(playback.position(at: Date()) - scrubPosition) <= 2 { clearScrub() }
            }
            .task(id: pendingSeek) {
                guard pendingSeek != nil else { return }
                // Keep the released thumb still while the player responds,
                // but always return to observed playback if it ignores seeking.
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                clearScrub()
            }
        }
    }

    private func clearScrub() {
        pendingSeek = nil
        scrubPosition = nil
        scrubTrack = nil
    }

    private func timestamp(_ interval: TimeInterval) -> String {
        let seconds = Int(min(604_800, max(0, interval)))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
