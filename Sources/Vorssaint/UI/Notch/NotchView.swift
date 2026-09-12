// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct NotchView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var music = NotchMusicService.shared
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var draggingModule: NotchModule?
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }

    var body: some View {
        surface
            .frame(width: service.surfaceSize.width, height: service.surfaceSize.height, alignment: .top)
            .background(.black)
            .foregroundStyle(.white)
            .contentShape(shape)
            .onHover(perform: service.hover)
            .onChange(of: contrast) {
                DispatchQueue.main.async { service.refreshPresentation(animated: false) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
            .environment(\.notchPresentation, true)
            .tint(.white)
            .accessibilityIdentifier("notch.surface")
    }

    private var shape: NotchShape {
        NotchShape(attached: service.geometry.isNotched,
                   radius: min(28, service.surfaceSize.height / 2))
    }

    @ViewBuilder private var surface: some View {
        if let options = service.captureControls {
            NotchCaptureControlsView(options: options, service: service)
                .padding(.horizontal, 18).padding(.top, service.geometry.safeContentTop)
        } else if service.expanded {
            expanded
        } else if service.dragPlaceholder {
            Label(text.dropHint, systemImage: "tray.and.arrow.down")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .padding(.top, service.geometry.safeContentTop)
        } else if let notice = service.notice {
            Button {
                service.open(notice.event == .clipboard ? .clipboard : .controls)
            } label: {
                NotchNoticeView(notice: notice)
                    .padding(.horizontal, 20)
                    .padding(.top, service.geometry.safeContentTop)
                    .padding(.bottom, 14)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(notice.title) \(notice.detail)")
            .accessibilityHint(text.open)
            .transition(.opacity)
        } else if service.peeking {
            navigation.padding(.horizontal, NotchLayout.horizontalInset).padding(.top, service.geometry.safeContentTop)
        } else if service.hasMusicActivity {
            NotchMusicStrip(service: service)
        } else {
            compact
                .transition(.opacity)
        }
    }

    private var compact: some View {
        Button { service.open() } label: {
            HStack(spacing: 0) {
                if service.idleContent != .none, service.geometry.restingWingWidth > 0 {
                    Group {
                        switch service.idleContent {
                        case .music:
                            if let artwork = music.artwork {
                                Image(nsImage: artwork).resizable().scaledToFill()
                                    .frame(width: min(22, service.geometry.menuBarHeight - 6), height: min(22, service.geometry.menuBarHeight - 6))
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                        case .battery: Image(systemName: "battery.100percent").font(.system(size: 12))
                        case .controls: Image(systemName: "slider.horizontal.3").font(.system(size: 12))
                        case .none: EmptyView()
                        }
                    }.frame(width: service.geometry.restingWingWidth)
                    Color.clear.frame(width: service.geometry.cameraWidth)
                    Group {
                        switch service.idleContent {
                        case .music:
                            if music.playback?.isPlaying == true { Image(systemName: "waveform").foregroundStyle(.mint) }
                        case .battery:
                            if let percent = service.power.chargePercent {
                                Text("\(percent)%").font(.system(size: 9, weight: .medium)).monospacedDigit()
                            }
                        case .controls: Image(systemName: "chevron.down").font(.system(size: 9))
                        case .none: EmptyView()
                        }
                    }.frame(width: service.geometry.restingWingWidth)
                } else { Color.clear }
            }
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text.open)
        .help(text.open)
    }

    private var showsDetail: Bool { service.showingAppPanel || service.selectedMetric != nil }

    private var expanded: some View {
        VStack(spacing: NotchLayout.spacing) {
            header.zIndex(1)
            if service.showingAppPanel || [.files, .music, .clipboard].contains(service.selected)
                || (service.selected == .captures && service.captureContent == nil) {
                content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if [.controls, .system, .tools].contains(service.selected), service.selectedMetric == nil {
                ViewThatFits(in: .vertical) {
                    content.fixedSize(horizontal: false, vertical: true)
                    ScrollView {
                        content.fixedSize(horizontal: false, vertical: true)
                    }.scrollIndicators(.automatic)
                }
                .id(service.selected)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
            } else {
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.bottom, 4)
                }
                .scrollIndicators(.automatic)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, NotchLayout.horizontalInset)
        .padding(.top, service.geometry.safeContentTop)
        .padding(.bottom, NotchLayout.bottomInset)
        .frame(width: service.expandedSize.width, height: service.expandedSize.height, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if showsDetail || service.modules.isEmpty {
                if showsDetail {
                    NotchIconButton(symbol: "chevron.left", title: l10n.s.obBack, action: service.goBack)
                }
                Text(service.showingAppPanel ? "Vorssaint" : service.selectedMetric?.title(l10n.s) ?? text.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                navigation.frame(maxWidth: .infinity, alignment: .leading)
            }
            Menu {
                Button {
                    service.pinned.toggle()
                } label: {
                    Label(service.pinned ? text.unpin : text.pin, systemImage: service.pinned ? "pin.slash" : "pin")
                }
                Divider()
                Button(action: service.openSettings) { Label(l10n.s.menuSettings, systemImage: "gearshape") }
            } label: {
                Label(l10n.s.keepAwakeOptions, systemImage: service.pinned ? "pin.fill" : "ellipsis")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(service.pinned ? .white : .secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(l10n.s.keepAwakeOptions)
            .help(l10n.s.keepAwakeOptions)
            NotchIconButton(symbol: "chevron.up", title: text.collapse, action: service.collapse)
        }
        .frame(height: NotchLayout.headerHeight)
    }

    private var navigation: some View {
        HStack(spacing: 2) {
            ForEach(Array(service.modules.enumerated()), id: \.element) { index, module in
                PanelReorderableItem(item: module, isEnabled: true,
                    order: Binding(get: { service.modules }, set: { modules in
                        UserDefaults.standard.set(modules.map(\.rawValue).joined(separator: ","), forKey: DefaultsKey.notchModuleOrder)
                    }), dragging: $draggingModule) {
                    Button { service.select(module) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: module.symbol)
                                .font(.system(size: 14, weight: .medium))
                            if service.selected == module, !service.peeking,
                               service.geometry.expandedWidth >= 440 || service.modules.count <= 5 {
                                Text(module.navigationTitle(l10n.language))
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1).minimumScaleFactor(0.9)
                                    .frame(width: 86, alignment: .leading)
                            }
                        }
                        .foregroundStyle(service.selected == module ? .white : .white.opacity(0.65))
                        .padding(.horizontal, service.selected == module ? 10 : 6)
                        .frame(minWidth: 26, minHeight: 32)
                        .background(.white.opacity(service.selected == module ? 0.12 : 0), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(NotchButtonStyle(cornerRadius: 16))
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .help("\(module.title(l10n.language))  ⌘\(index + 1)")
                    .accessibilityLabel(module.title(l10n.language))
                    .accessibilityAddTraits(service.selected == module ? .isSelected : [])
                    .accessibilityIdentifier("notch.module.\(module.rawValue)")
                }
            }
        }
        .frame(height: NotchLayout.navigationHeight)
    }

    @ViewBuilder private var content: some View {
        if service.showingAppPanel {
            MenuPanelView(notchSize: service.contentSize)
        } else if let metric = service.selectedMetric {
            MetricDetailView(kind: metric)
        } else if service.modules.isEmpty {
            NotchEmptyView(symbol: "slider.horizontal.3", message: text.empty)
        } else {
            switch service.selected {
            case .controls: NotchControlsView(service: service)
            case .mixer: MixerSection(collapsible: false)
            case .music: NotchMusicView(compact: service.geometry.usesCompactContent)
            case .clipboard: NotchClipboardView(service: service)
            case .captures:
                if let capture = service.captureContent {
                    capture.frame(maxWidth: .infinity)
                } else {
                    RecentCapturesView(onClose: nil, notchHeight: service.contentSize.height)
                }
            case .files: NotchFilesView(service: service)
            case .system: NotchSystemView(columns: service.geometry.systemColumns, select: service.showMetric)
            case .tools: QuickLauncherView(notchSize: service.contentSize)
            }
        }
    }
}

struct NotchShape: Shape {
    var attached: Bool
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard attached else { return Path(roundedRect: rect, cornerRadius: radius) }
        let shoulder = min(14, rect.height * 0.28)
        let bottom = min(radius, rect.height / 2, (rect.width - shoulder * 2) / 2)
        let tangent: CGFloat = 0.55228475
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addCurve(to: CGPoint(x: rect.width - shoulder, y: shoulder),
                      control1: CGPoint(x: rect.width - shoulder * tangent, y: 0),
                      control2: CGPoint(x: rect.width - shoulder, y: shoulder * (1 - tangent)))
        path.addLine(to: CGPoint(x: rect.width - shoulder, y: rect.height - bottom))
        path.addCurve(to: CGPoint(x: rect.width - shoulder - bottom, y: rect.height),
                      control1: CGPoint(x: rect.width - shoulder, y: rect.height - bottom * (1 - tangent)),
                      control2: CGPoint(x: rect.width - shoulder - bottom * (1 - tangent), y: rect.height))
        path.addLine(to: CGPoint(x: shoulder + bottom, y: rect.height))
        path.addCurve(to: CGPoint(x: shoulder, y: rect.height - bottom),
                      control1: CGPoint(x: shoulder + bottom * (1 - tangent), y: rect.height),
                      control2: CGPoint(x: shoulder, y: rect.height - bottom * (1 - tangent)))
        path.addLine(to: CGPoint(x: shoulder, y: shoulder))
        path.addCurve(to: .zero,
                      control1: CGPoint(x: shoulder, y: shoulder * (1 - tangent)),
                      control2: CGPoint(x: shoulder * tangent, y: 0))
        path.closeSubpath()
        return path
    }
}

struct NotchNoticeView: View {
    let notice: NotchNotice
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: notice.symbol)
                .font(.system(size: 23, weight: .medium))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(notice.title).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(notice.detail).monospacedDigit()
                }
                .font(.system(size: 12, weight: .medium))
                if let level = notice.level {
                    ProgressView(value: min(1, max(0, level)))
                        .progressViewStyle(.linear)
                        .tint(.white)
                }
            }
        }
        .foregroundStyle(.white)
        .frame(height: 40)
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
        .accessibilityElement(children: .combine)
    }
}

extension NotchModule: PanelOrderItem {
    func navigationTitle(_ language: AppLanguage) -> String {
        let text = FeatureStrings.notch(language)
        switch self {
        case .music: return text.music
        case .mixer: return text.volume
        case .captures: return text.captures
        default: return title(language)
        }
    }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .controls: return FeatureStrings.notch(language).controls
        case .mixer: return L10n.shared.s.mixerSection
        case .music: return FeatureStrings.radialMenu(language).mediaNowPlaying
        case .clipboard: return FeatureStrings.clipboard(language).title
        case .captures: return FeatureStrings.recentCaptures(language).title
        case .files: return FeatureStrings.notch(language).files
        case .system: return FeatureStrings.notch(language).system
        case .tools: return FeatureStrings.notch(language).tools
        }
    }
}
