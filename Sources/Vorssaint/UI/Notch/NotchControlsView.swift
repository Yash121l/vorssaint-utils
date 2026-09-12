// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct NotchControlsView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.brightnessControlEnabled) private var brightnessEnabled = false

    var body: some View {
        VStack(spacing: 18) {
            let items = NotchSupport.controls()
            if items.contains(.volume) || items.contains(.brightness) {
                if service.geometry.hasSideBySideLevels {
                    HStack(spacing: 12) { levels(items) }
                } else {
                    VStack(spacing: 18) { levels(items) }
                }
            }
            let shortcuts = items.filter { $0 != .volume && $0 != .brightness }
            if !shortcuts.isEmpty {
                NotchTileGrid(items: shortcuts, columns: service.geometry.controlColumns) { item in
                    shortcut(item)
                }
            }
            if shortcuts.isEmpty, !items.contains(.volume), !items.contains(.brightness) {
                NotchEmptyView(symbol: "slider.horizontal.3", message: FeatureStrings.notch(l10n.language).empty)
            }
        }
    }

    @ViewBuilder private func levels(_ items: [NotchControlItem]) -> some View {
        if items.contains(.volume) { NotchAudioControls(notch: service) }
        if items.contains(.brightness) {
            if brightnessEnabled { NotchBrightnessControls() }
            else {
                VStack(alignment: .leading, spacing: 16) {
                    Label(FeatureStrings.notch(l10n.language).brightness, systemImage: "sun.max.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Button(l10n.s.menuSettings) {
                        service.perform {
                            SettingsRouter.shared.request(AppFeature.brightness.settingsDestination)
                            (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
                        }
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: NotchLayout.controlHeight, alignment: .leading)
                .modifier(NotchControlSurface(cornerRadius: 18))
            }
        }
    }

    @ViewBuilder private func shortcut(_ item: NotchControlItem) -> some View {
        switch item {
        case .keepAwake: NotchAwakeButton()
        case .microphone: NotchMicButton()
        case .screenshot:
            NotchActionTile(symbol: "camera.viewfinder", title: item.title(l10n)) {
                service.perform { ScreenshotService.shared.capture() }
            }
        case .recording: NotchRecorderButton(service: service)
        case .speedTest:
            NotchActionTile(symbol: "speedometer", title: item.title(l10n)) { service.showMetric(.network) }
        case .panel:
            NotchActionTile(symbol: "rectangle.topthird.inset.filled", title: item.title(l10n)) { service.openAppPanel() }
        case .mixer:
            NotchActionTile(symbol: "slider.vertical.3", title: item.title(l10n)) { service.select(.mixer) }
        case .commandBar:
            NotchActionTile(symbol: "command", title: item.title(l10n)) { service.perform { CommandBarService.shared.show() } }
        case .volume, .brightness: EmptyView()
        }
    }
}

extension NotchControlItem {
    func title(_ l10n: L10n) -> String {
        switch self {
        case .volume: return FeatureStrings.notch(l10n.language).volume
        case .brightness: return FeatureStrings.notch(l10n.language).brightness
        case .keepAwake: return l10n.s.keepAwakeTitle
        case .microphone: return l10n.s.micMuteName
        case .screenshot: return FeatureStrings.recentCaptures(l10n.language).screenshot
        case .recording: return FeatureStrings.recorder(l10n.language).pageTitle
        case .speedTest: return l10n.s.speedTestRun
        case .panel: return FeatureStrings.notch(l10n.language).panel
        case .mixer: return l10n.s.mixerSection
        case .commandBar: return FeatureStrings.commandBar(l10n.language).pageTitle
        }
    }
}

struct NotchAudioControls: View {
    @ObservedObject var notch: NotchService = .shared
    var inline = false
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @ObservedObject private var l10n = L10n.shared
    private var level: Double? { mixer.systemOutputVolume.map { mixer.systemOutputMuted == true ? 0 : $0 } }
    private var deviceName: String {
        mixer.outputDevices.first(where: { $0.uid == mixer.currentOutputDeviceUID })?.name ?? l10n.s.mixerSystemOutputTitle
    }

    var body: some View {
        VStack(spacing: 4) {
            if inline {
                HStack(spacing: 10) {
                    mute
                    slider
                    outputMenu
                }
                .frame(height: 32)
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 7) {
                        mute
                        Text(FeatureStrings.notch(l10n.language).volume).lineLimit(1)
                        Spacer(minLength: 0)
                        if let level { Text("\(Int((level * 100).rounded()))%").monospacedDigit() }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    slider
                    outputMenu.frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: NotchLayout.controlHeight)
                .modifier(NotchControlSurface(cornerRadius: 18))
            }
            if let error = mixer.outputSwitchError {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1).help(error)
            }
        }
    }

    private var mute: some View {
        Button {
            if let muted = mixer.systemOutputMuted { mixer.requestOutputAdjustment(muted: !muted) }
        } label: {
            Image(systemName: mixer.systemOutputMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .medium)).frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 6))
        .disabled(mixer.systemOutputMuted == nil)
        .accessibilityLabel(mixer.systemOutputMuted == true ? l10n.s.actionUnmute : l10n.s.actionMute)
    }

    @ViewBuilder private var slider: some View {
        if let level {
            NotchLevelSlider(value: Binding(get: { level }, set: { mixer.requestOutputAdjustment(volume: $0) }),
                             label: FeatureStrings.notch(l10n.language).volume)
                .frame(height: inline ? 24 : 28)
        } else {
            Text(l10n.s.mixerOutputUnavailable).font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        }
    }

    private var outputMenu: some View {
        Menu {
            ForEach(mixer.outputDevices.filter(\.canBeDefaultOutput)) { device in
                Button { _ = mixer.setUniversalOutputDeviceUID(device.uid) } label: {
                    if device.uid == mixer.currentOutputDeviceUID { Label(device.name, systemImage: "checkmark") }
                    else { Text(device.name) }
                }
            }
            if notch.modules.contains(.mixer) {
                Divider()
                Button { notch.select(.mixer) } label: { Label(l10n.s.mixerSection, systemImage: "slider.vertical.3") }
            }
        } label: {
            HStack(spacing: 5) {
                if inline { Image(systemName: "airplay.audio").font(.system(size: 14)) }
                else {
                    Text(deviceName).font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: 154, alignment: .leading)
                }
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
        .help(deviceName).accessibilityLabel(l10n.s.mixerSystemOutputTitle)
    }
}

private struct NotchBrightnessControls: View {
    @ObservedObject private var service = BrightnessService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var selectedID: CGDirectDisplayID?
    private var displays: [BrightnessDisplay] { service.displays.filter { $0.isActive && $0.method != nil } }
    private var display: BrightnessDisplay? {
        displays.first(where: { $0.id == selectedID }) ?? displays.first(where: \.isBuiltIn) ?? displays.first
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                Label(FeatureStrings.notch(l10n.language).brightness, systemImage: "sun.max.fill")
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let display { Text("\(BrightnessSupport.wholePercent(display.brightness))%").monospacedDigit() }
            }
            .font(.system(size: 12, weight: .semibold))
            if let display {
                NotchLevelSlider(value: Binding(get: { display.brightness }, set: {
                    service.setBrightness($0, for: display.id, showOSD: true)
                }), label: FeatureStrings.notch(l10n.language).brightness)
                    .frame(height: 28)
                Menu {
                    ForEach(displays) { item in
                        Button(item.name) { selectedID = item.id }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(display.name).font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: 154, alignment: .leading)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }.foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(FeatureStrings.brightness(l10n.language).noDisplays)
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: NotchLayout.controlHeight)
        .modifier(NotchControlSurface(cornerRadius: 18))
        .onAppear { service.refresh() }
    }
}

struct NotchActionTile: View {
    let symbol: String
    let title: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                    .foregroundStyle(active ? .mint : .white.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(active ? Color.mint.opacity(0.17) : Color.white.opacity(0.075), in: Circle())
                Text(title).font(.system(size: 11, weight: .medium))
                    .lineLimit(2).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 28, alignment: .top)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity).frame(height: NotchLayout.shortcutHeight)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 14))
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private struct NotchAwakeButton: View {
    @ObservedObject private var service = KeepAwakeManager.shared
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        NotchActionTile(symbol: service.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
                        title: l10n.s.keepAwakeTitle, active: service.isActive, action: service.toggle)
    }
}

private struct NotchMicButton: View {
    @ObservedObject private var service = MicMuteService.shared
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        NotchActionTile(symbol: service.isMuted ? "mic.slash.fill" : "mic.fill",
                        title: service.isMuted ? l10n.s.micUnmuteName : l10n.s.micMuteName,
                        active: service.isMuted, action: service.toggle)
    }
}

private struct NotchRecorderButton: View {
    let service: NotchService
    @ObservedObject private var recorder = ScreenRecorderService.shared
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        NotchActionTile(symbol: recorder.isRecording ? "stop.circle.fill" : "record.circle",
                        title: FeatureStrings.recorder(l10n.language).pageTitle,
                        active: recorder.isRecording) {
            service.perform { recorder.toggle() }
        }
    }
}
