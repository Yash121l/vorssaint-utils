// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import IOKit.ps
import SwiftUI

struct NotchNotice: Equatable {
    let event: NotchEvent
    let title: String
    let detail: String
    let symbol: String
    var level: Double? = nil
    var notification: NotchNotificationContent? = nil
    var notificationID: UUID? = nil

    var accessibilityText: String {
        notification?.accessibilityText ?? [title, detail].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Owns presentation only. Clipboard, files, captures, audio and metrics keep
/// their original owners, gates and privacy rules.
final class NotchService: ObservableObject {
    static let shared = NotchService()

    @Published private(set) var geometry = NotchGeometry(
        screen: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 0, cameraWidth: 0)
    @Published private(set) var expanded = false
    @Published private(set) var peeking = false
    @Published private(set) var dragPlaceholder = false
    @Published private(set) var selectedMetric: MetricDetailKind?
    @Published private(set) var captureControls: ScreenCaptureSelectionOptions?
    @Published var pinned = false
    @Published private(set) var selected: NotchModule = .controls
    @Published private(set) var showingAppPanel = false
    @Published private(set) var modules: [NotchModule] = []
    @Published private(set) var notice: NotchNotice?
    @Published private(set) var captureContent: AnyView?
    @Published private(set) var power = PowerReading()
    @Published private var musicDetailVisible = false

    private var windowHost: NotchWindowHost?
    private var panel: NotchPanel? { windowHost?.panel }
    private var captureControlsCancel: (() -> Void)?
    private var captureControlsSubscription: AnyCancellable?
    private var heldDrag = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var subscriptions = Set<AnyCancellable>()
    private var eventMonitors: [Any] = []
    private var captureControlsMonitors: [Any] = []
    private var hoverWork: DispatchWorkItem?
    private var noticeWork: DispatchWorkItem?
    private var powerSource: CFRunLoopSource?
    private var powerSampler: PowerSampler?
    private var captureID: UUID?
    private var captureFallback: (() -> Void)?
    private var captureClose: (() -> Void)?
    private var captureHover: ((Bool) -> Void)?
    private var inside = false
    private var openedByHover = false
    private var trackingMenu = false
    private var keepsWorkingSurface: Bool {
        pinned || trackingMenu || NSApp.modalWindow != nil || panel?.attachedSheet != nil
            || (expanded && selected == .calendar && Permissions.shared.keepsCalendarPrompt)
            || CameraPreviewService.shared.keepsNotchPermissionPrompt
            || (expanded && selected == .captures && captureContent != nil)
            || (expanded && selected == .tools && (QuickLauncherService.shared.activeUtility != nil || QuickLauncherService.shared.isEditing))
    }
    private var running = false
    private var session = NotchSessionState()
    private var suspended: Bool { !session.canPresent }
    private var settingsSignature = ""
    private var gesture = NotchGestureSupport()
    private var volumeBaseline: Double?
    private var muteBaseline: Bool?
    private var notchNeedsMonitor = false
    private var menuSpaceTimer: Timer?
    private var menuSpaceReading = false
    private var menuSpaceGeneration = 0
    private let menuSpaceQueue = DispatchQueue(label: "com.vorssaint.notch-menu-space", qos: .utility)

    private init() {}

    var idleContent: NotchIdleContent {
        NotchSupport.visibleIdleContent(isPlaying: NotchMusicService.shared.playback?.isPlaying == true)
    }

    var hasTimerActivity: Bool {
        NotchTimerSupport.isEnabled() && NotchTimerService.shared.session.hasSession
    }

    var hasDownloadActivity: Bool {
        NotchSupport.routes(.download)
            && NotchDownloadService.shared.items.contains { $0.active && !$0.completed }
    }

    var hasMusicActivity: Bool {
        NotchSupport.showsMusicActivity(isPlaying: NotchMusicService.shared.playback?.isPlaying == true)
    }

    var compactActivity: NotchCompactActivity? {
        NotchSupport.compactActivity(timer: hasTimerActivity, downloads: hasDownloadActivity, music: hasMusicActivity)
    }

    private var compactActivityIsVisible: Bool {
        !expanded && !peeking && !dragPlaceholder && notice == nil && captureControls == nil
            && compactActivity != nil
    }

    private var compactMusicIsVisible: Bool { compactActivityIsVisible && compactActivity == .music }

    var compactActivityGeometry: NotchGeometry {
        switch compactActivity {
        case .music: return geometry.compactMusicGeometry
        case .timer: return geometry.compactTimerGeometry(showsDownloads: hasDownloadActivity)
        default: return geometry
        }
    }

    private var presentationGeometry: NotchGeometry {
        compactActivityIsVisible ? compactActivityGeometry.compactActivityGeometry : geometry
    }

    var expandedSize: CGSize {
        let controls = NotchSupport.controls()
        let sliders = controls.filter { $0 == .volume || $0 == .brightness }.count
        let shortcuts = controls.count - sliders
        let musicExtras = NotchLyricsSupport.isEnabled() || NotchQueueSupport.isEnabled()
        return geometry.expandedSize(module: showingAppPanel ? .tools : selected,
                                     detail: selectedMetric != nil, controlRows: (shortcuts + geometry.controlColumns - 1) / geometry.controlColumns,
                                     sliderCount: sliders, musicHasContent: NotchMusicService.shared.playback != nil,
                                     musicExtraHeight: musicExtras ? (musicDetailVisible ? 260 : 44) : 0,
                                     fileMediaVisible: AppFeature.mediaTools.isAvailable && NotchFileToolsService.shared.mediaSession != nil,
                                     systemRows: (NotchSupport.systemCardCount(hasBattery: PowerSampler.hasInternalBattery)
                                        + geometry.systemColumns - 1) / geometry.systemColumns,
                                     timerHasSession: NotchTimerService.shared.session.hasSession)
    }
    var contentSize: CGSize { geometry.contentSize(for: expandedSize) }
    var surfaceSize: CGSize {
        if let captureControls {
            return CGSize(width: geometry.expanded.width,
                          height: geometry.safeContentTop + 28 + 12 + NotchLayout.shortcutHeight + 16
                            + (captureControls.selectedTool.capturesAudio ? 40 : 0))
        }
        if expanded { return expandedSize }
        if dragPlaceholder { return CGSize(width: geometry.peek.width, height: geometry.safeContentTop + 66) }
        if let notice { return geometry.noticeSize(notification: notice.notification != nil) }
        if peeking { return geometry.peek }
        if compactActivity != nil { return compactActivityGeometry.compactActivitySize }
        return geometry.restingSize(showsContent: idleContent != .none)
    }

    var presentationWindow: NSPanel? { panel }
    var acceptsSystemFeedback: Bool { running && !suspended && panel != nil }

    var protectedWindowIDs: Set<CGWindowID> {
        guard !NotchSupport.showsInCaptures(),
              let panel, panel.isVisible, panel.windowNumber > 0 else { return [] }
        return [CGWindowID(panel.windowNumber)]
    }

    var captureVisibleWindowIDs: Set<CGWindowID> {
        guard NotchSupport.showsInCaptures(), let panel, panel.isVisible,
              panel.windowNumber > 0 else { return [] }
        return [CGWindowID(panel.windowNumber)]
    }

    /// While a capture is choosing an area on screen, the notch is part of the
    /// capture interface, so its window is kept out of the pixels no matter
    /// what the everyday "show in captures" preference says. This lets people
    /// grab whatever sits behind the notch cleanly.
    var captureChromeWindowIDs: Set<CGWindowID> {
        guard running, let panel, panel.isVisible, panel.windowNumber > 0 else { return [] }
        return [CGWindowID(panel.windowNumber)]
    }

    func syncWithPreferences() {
        guard NotchSupport.isEnabled() else { stop(); return }
        if !running {
            running = true
            installObservers()
        }
        if !NotchTimerSupport.isEnabled() { NotchTimerService.shared.stop() }
        // Requested file work can continue while locked, but disabling its
        // feature must still cancel it before presentation resumes.
        NotchFileToolsService.shared.syncWithPreferences()
        guard !suspended else { return }
        refreshModules()
        NotchDownloadService.shared.syncWithPreferences()
        NotchCalendarService.shared.syncWithPreferences()
        NotchNotificationService.shared.syncWithPreferences()
        updateScreen()
        syncGestures()
        NotchTimerService.shared.syncWithPreferences()
        NotchAccessoryService.shared.syncWithPreferences()
        let signature = NotchEvent.allCases.map { String(NotchSupport.routes($0)) }.joined()
            + NotchSupport.idleContent().rawValue + String(NotchSupport.watchesMusicActivity())
            + modules.map(\.rawValue).joined()
            + String(NotchSupport.routesShelf()) + String(NotchSupport.revealsShelfDrag())
            + String(NotchSupport.routesCaptureControls())
        if signature != settingsSignature {
            settingsSignature = signature
            bindEvents()
            if AppFeature.shelf.isAvailable { ShelfService.shared.syncWithPreferences() }
        }
        if !NotchSupport.routes(.capture), captureContent != nil {
            let fallback = captureFallback
            clearCapture()
            fallback?()
        }
        if captureControls != nil, !NotchSupport.routesCaptureControls() { cancelCaptureControls() }
        if let notice, !NotchSupport.routes(notice.event) { dismissNotice() }
        syncVisibleConsumers()
        refreshPresentation(animated: false)
        if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
        if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
    }

    private func refreshModules() {
        let updated = NotchSupport.modules()
        if modules != updated { modules = updated }
        let selection = modules.contains(selected) ? selected : modules.first ?? .controls
        if selected != selection { selected = selection }
    }

    func stop(restoreCapture: Bool = true) {
        NotchLyricsService.shared.stop()
        NotchFileToolsService.shared.stop()
        guard running else { return }
        running = false
        NotchTimerService.shared.stop()
        NotchAccessoryService.shared.stop()
        let cancelCapture = captureControlsCancel
        endCaptureControls()
        cancelCapture?()
        let fallback = restoreCapture ? captureFallback : captureClose
        clearCapture()
        tearDownPresentation()
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        session = NotchSessionState()
        if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
        if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
        if AppFeature.shelf.isAvailable { ShelfService.shared.syncWithPreferences() }
        fallback?()
    }

    private func tearDownPresentation() {
        musicDetailVisible = false
        panel?.handleScroll = nil
        gesture = NotchGestureSupport()
        stopMenuSpaceMonitoring()
        geometry.compactSideRoom = nil
        hoverWork?.cancel(); hoverWork = nil
        noticeWork?.cancel(); noticeWork = nil
        subscriptions.removeAll()
        stopPower()
        NotchMusicService.shared.stop()
        NotchTimerService.shared.suspend()
        CameraPreviewService.shared.hideEmbedded()
        NotchAccessoryService.shared.suspend()
        NotchDownloadService.shared.stop()
        NotchCalendarService.shared.stop()
        NotchNotificationService.shared.stop()
        settingsSignature = ""
        expanded = false
        peeking = false
        dragPlaceholder = false
        heldDrag = false
        selectedMetric = nil
        pinned = false
        notice = nil
        showingAppPanel = false
        inside = false
        openedByHover = false
        removeEventMonitors()
        removeCaptureControlsClickThrough()
        releaseMonitor()
        windowHost?.close()
        windowHost = nil
    }

    func open(_ module: NotchModule? = nil, pinned: Bool = false, takeFocus: Bool = true,
              appPanel: Bool = false, metric: MetricDetailKind? = nil, feedback: Bool = true) {
        guard NotchSupport.isEnabled(), !suspended else { return }
        if !running || self.panel == nil { syncWithPreferences() }
        else { refreshModules() }
        guard let panel else { return }
        let destination = module.flatMap { modules.contains($0) ? $0 : nil } ?? selected
        let changesPresentation = !expanded || selected != destination
            || showingAppPanel != appPanel || selectedMetric != metric
        (NSApp.delegate as? AppDelegate)?.closePopover(preservingNotch: true)
        if !expanded, modules.contains(.clipboard) { ClipboardHistoryService.shared.rememberPasteTarget() }
        panel.acceptsKeyFocus = true
        hoverWork?.cancel()
        mutatePresentation(transitionContent: changesPresentation ? (expanded ? .replace : .reveal) : .none) {
            showingAppPanel = appPanel
            if selected != destination { selected = destination }
            if pinned { self.pinned = true }
            selectedMetric = metric
            peeking = false
            openedByHover = !takeFocus
            expanded = true
        }
        inside = geometry.frame(for: expandedSize).contains(NSEvent.mouseLocation)
        installEventMonitors()
        syncVisibleConsumers()
        if takeFocus { panel.makeKey() }
        if feedback, changesPresentation { provideHapticFeedback() }
    }

    func collapse() {
        guard captureControls == nil, !heldDrag else { return }
        pinned = false
        hoverWork?.cancel(); hoverWork = nil
        mutatePresentation(transitionContent: expanded || peeking ? .dismiss : .none) {
            expanded = false
            openedByHover = false
            peeking = false
            selectedMetric = nil
            showingAppPanel = false
        }
        panel?.acceptsKeyFocus = false
        panel?.resignKey()
        removeEventMonitors()
        syncVisibleConsumers()
    }

    func toggle() { expanded ? collapse() : open() }

    func setMusicDetailsVisible(_ visible: Bool) {
        guard visible != musicDetailVisible else { return }
        mutatePresentation { musicDetailVisible = visible }
    }

    @discardableResult
    func showClipboard(toggle: Bool = false) -> Bool {
        guard running, !suspended, NotchSupport.routesClipboardWindow() else { return false }
        if toggle, expanded, selected == .clipboard, !showingAppPanel { collapse() }
        else { open(.clipboard) }
        return true
    }

    func hover(_ entered: Bool) {
        inside = entered
        captureHover?(entered)
        hoverWork?.cancel(); hoverWork = nil
        guard !pinned, captureControls == nil, !heldDrag, !keepsWorkingSurface else { return }
        if entered {
            guard notice == nil, !expanded, !peeking, !dragPlaceholder,
                  UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover) else { return }
            if compactActivity != nil, compactActivityGeometry.compactActivityWingWidth > 0,
               !UserDefaults.standard.bool(forKey: DefaultsKey.notchHoverExpands) { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.inside, self.captureControls == nil else { return }
                if UserDefaults.standard.bool(forKey: DefaultsKey.notchHoverExpands) {
                    self.open(self.compactActivity?.module, takeFocus: false)
                } else {
                    self.mutatePresentation(transitionContent: .reveal) { self.peeking = true }
                    self.provideHapticFeedback()
                }
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
        } else if NotchSupport.closesOnPointerExit(expanded: expanded, peeking: peeking, openedByHover: openedByHover) {
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.inside, !self.pinned, !self.heldDrag, !self.keepsWorkingSurface,
                      !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation),
                      NotchSupport.closesOnPointerExit(expanded: self.expanded, peeking: self.peeking, openedByHover: self.openedByHover) else { return }
                self.collapse()
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: work)
        }
    }

    func select(_ module: NotchModule) {
        guard modules.contains(module) else { return }
        open(module)
    }

    func openAppPanel(toggle: Bool = false) {
        if toggle, expanded, showingAppPanel { collapse(); return }
        MenuPanelFocus.shared.showNormalPanel()
        open(.controls, appPanel: true)
    }

    func openQuickPanel(toggle: Bool = false) -> Bool {
        guard NotchSupport.routesQuickPanel(), acceptsSystemFeedback else { return false }
        if toggle, expanded, selected == .tools { collapse() }
        else { open(.tools) }
        return true
    }

    func openShelf(toggle: Bool = false) -> Bool {
        guard NotchSupport.routesShelf(), acceptsSystemFeedback else { return false }
        if toggle, expanded, selected == .files { collapse() }
        else { open(.files) }
        return true
    }

    func showMetric(_ metric: MetricDetailKind) {
        guard metric.panelSection.isAvailable else { return }
        open(.system, metric: metric)
    }

    func goBack() {
        let changesPresentation = selectedMetric != nil || showingAppPanel
        mutatePresentation(transitionContent: changesPresentation ? .replace : .none) { selectedMetric = nil; showingAppPanel = false }
        syncVisibleConsumers()
        if changesPresentation { provideHapticFeedback() }
    }

    func provideHapticFeedback() {
        guard acceptsSystemFeedback, panel?.isVisible == true, NotchSupport.usesHapticFeedback() else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    func fileDragChanged(_ active: Bool, internalDrag: Bool = false) {
        guard running, !suspended, NotchSupport.routesShelf() else { return }
        heldDrag = active && internalDrag
        if active, !internalDrag, NotchSupport.revealsShelfDrag(), !expanded {
            mutatePresentation { dragPlaceholder = true; peeking = false }
        } else if !active {
            mutatePresentation { dragPlaceholder = false }
            inside = windowHost?.contains(NSEvent.mouseLocation) == true
            if !inside, !pinned { hover(false) }
        }
    }

    func presentCaptureControls(_ options: ScreenCaptureSelectionOptions, cancel: @escaping () -> Void) {
        guard acceptsSystemFeedback else { cancel(); return }
        pinned = false
        captureControlsCancel = cancel
        captureControls = options
        captureControlsSubscription = options.$selectedTool.dropFirst()
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.refreshPresentation()
                self?.updateCaptureControlsClickThrough()
            }
        expanded = false
        peeking = false
        notice = nil
        hoverWork?.cancel()
        removeEventMonitors()
        panel?.acceptsKeyFocus = true
        panel?.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        refreshPresentation()
        panel?.orderFrontRegardless()
        panel?.makeKey()
        installCaptureControlsClickThrough()
        syncVisibleConsumers()
    }

    /// The capture-controls window covers the top center of the screen, over
    /// the selection surface. Only its visible controls should catch the
    /// mouse; everywhere else the click falls through to the selection beneath,
    /// so a region under the notch can still be dragged or a window clicked.
    private func updateCaptureControlsClickThrough() {
        guard let panel, captureControls != nil else { return }
        let overControls = windowHost?.contains(NSEvent.mouseLocation) == true
        if panel.ignoresMouseEvents != !overControls { panel.ignoresMouseEvents = !overControls }
    }

    private func installCaptureControlsClickThrough() {
        guard captureControlsMonitors.isEmpty else { return }
        // Posting moved events lets the click-through state settle before the
        // pointer reaches a control, so the controls stay clickable.
        panel?.acceptsMouseMovedEvents = true
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged,
                                            .rightMouseDragged, .otherMouseDragged]
        if let token = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            self?.updateCaptureControlsClickThrough()
        }) { captureControlsMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.updateCaptureControlsClickThrough(); return event
        }) { captureControlsMonitors.append(token) }
        updateCaptureControlsClickThrough()
    }

    private func removeCaptureControlsClickThrough() {
        captureControlsMonitors.forEach(NSEvent.removeMonitor)
        captureControlsMonitors.removeAll()
        panel?.ignoresMouseEvents = false
        panel?.acceptsMouseMovedEvents = false
    }

    func endCaptureControls() {
        guard captureControls != nil else { return }
        geometry.compactSideRoom = nil
        captureControls = nil
        captureControlsSubscription = nil
        captureControlsCancel = nil
        removeCaptureControlsClickThrough()
        panel?.level = .statusBar
        panel?.acceptsKeyFocus = false
        panel?.resignKey()
        refreshPresentation()
        syncMenuSpaceMonitoring()
    }

    func cancelCaptureControls() { captureControlsCancel?() }

    func openSettings() {
        collapse()
        SettingsRouter.shared.request(FeatureSettingsDestination(.notch))
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }

    func perform(_ action: @escaping () -> Void) {
        collapse()
        if let windowHost { windowHost.whenSettled(action) }
        else { DispatchQueue.main.async(execute: action) }
    }

    var canAcceptFileDrop: Bool {
        acceptsSystemFeedback && captureControls == nil && modules.contains(.files)
            && AppFeature.shelf.isAvailable
    }

    func accept(_ pasteboard: NSPasteboard) -> Bool {
        guard canAcceptFileDrop else { return false }
        let accepted = ShelfService.shared.accept(pasteboard: pasteboard)
        if accepted { heldDrag = false; dragPlaceholder = false; open(.files) }
        return accepted
    }

    @discardableResult
    func show(_ incoming: NotchNotice) -> Bool {
        guard running, !suspended, panel != nil, NotchSupport.routes(incoming.event),
              NotchSupport.shouldReplace(notice?.event, with: incoming.event) else { return false }
        noticeWork?.cancel()
        // Slider and key bursts only replace the displayed value. They never
        // restart a window resize or enqueue another layout animation.
        let transition: NotchContentTransition = !noticeCanPresent ? .none
            : notice == nil ? .reveal : notice?.event != incoming.event ? .replace : .none
        mutatePresentation(transitionContent: transition) { notice = incoming }
        let work = DispatchWorkItem { [weak self] in self?.dismissNotice() }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + incoming.event.duration, execute: work)
        return true
    }

    func activateNotice(_ selectedNotice: NotchNotice) {
        guard notice == selectedNotice else { return }
        if let id = selectedNotice.notificationID {
            guard NotchNotificationService.shared.openingID == nil else { return }
            NotchNotificationService.shared.open(id) { [weak self] result in
                guard let self else { return }
                if self.notice?.notificationID == id { self.dismissNotice() }
                if result == .unavailable || result == .uncertain { self.open(.notifications) }
            }
            return
        }
        open(selectedNotice.event == .download ? .downloads : selectedNotice.event == .timer ? .timer
             : selectedNotice.event == .accessory ? .system : selectedNotice.event == .systemNotification ? .notifications
             : selectedNotice.event == .clipboard ? .clipboard : .controls)
    }

    func showBrightness(_ level: Double) -> Bool {
        let text = FeatureStrings.notch(L10n.shared.language)
        return show(NotchNotice(event: .brightness, title: text.brightness,
                                detail: "\(BrightnessSupport.wholePercent(level))%",
                                symbol: "sun.max.fill", level: level))
    }

    @discardableResult
    func showKeyboardLight(_ level: Double) -> Bool {
        guard level.isFinite, (0...1).contains(level) else { return false }
        return show(NotchNotice(event: .keyboardLight,
                                title: FeatureStrings.brightness(L10n.shared.language).keyboardLight,
                                detail: "\(BrightnessSupport.wholePercent(level))%",
                                symbol: "keyboard", level: level))
    }

    private func dismissNotice() {
        noticeWork?.cancel(); noticeWork = nil
        let transition: NotchContentTransition = notice != nil && noticeCanPresent ? .dismiss : .none
        mutatePresentation(transitionContent: transition) { notice = nil }
    }

    private var noticeCanPresent: Bool { !expanded && !dragPlaceholder && captureControls == nil }

    func presentCapture(id: UUID, content: AnyView, fallback: @escaping () -> Void,
                        close: @escaping () -> Void, hover: @escaping (Bool) -> Void) -> Bool {
        guard running, !suspended, panel != nil, NotchSupport.routes(.capture) else { return false }
        let keepOpen = expanded && pinned
        captureID = id
        captureContent = content
        captureFallback = fallback
        captureClose = close
        captureHover = hover
        open(.captures, pinned: keepOpen,
             takeFocus: UserDefaults.standard.bool(forKey: DefaultsKey.screenshotPreviewTakesFocus), feedback: false)
        captureHover?(inside)
        return true
    }

    func removeCapture(id: UUID) {
        guard captureID == id else { return }
        clearCapture()
        if expanded, selected == .captures, !pinned { collapse() }
    }

    private func clearCapture() {
        captureID = nil
        captureContent = nil
        captureFallback = nil
        captureClose = nil
        captureHover = nil
    }

    private func mutatePresentation(transitionContent: NotchContentTransition = .none, _ change: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
        refreshPresentation(transitionContent: transitionContent)
    }

    func refreshPresentation(animated: Bool = true, transitionContent: NotchContentTransition = .none) {
        let active = expanded || peeking || notice != nil || dragPlaceholder || captureControls != nil || compactActivityIsVisible
        guard active || geometry.isNotched || geometry.compactSideRoom != nil else {
            panel?.orderOut(nil)
            return
        }
        windowHost?.present(size: surfaceSize, geometry: presentationGeometry, animated: animated,
                            transitionContent: transitionContent)
        if panel?.isVisible != true { panel?.orderFrontRegardless() }
    }

    private func stopMenuSpaceMonitoring() {
        menuSpaceTimer?.invalidate()
        menuSpaceTimer = nil
        menuSpaceGeneration += 1
    }

    private func syncMenuSpaceMonitoring() {
        let wanted = running && !suspended && !expanded && captureControls == nil
            && (idleContent != .none || compactActivity != nil || !geometry.isNotched)
        guard wanted else { stopMenuSpaceMonitoring(); return }
        guard menuSpaceTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.readMenuSpace() }
        timer.tolerance = 0.2
        menuSpaceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        readMenuSpace()
    }

    private func invalidateMenuSpace(resetGeometry: Bool = false) {
        menuSpaceGeneration += 1
        // Keep the last measured layout until its replacement arrives. Clearing
        // it first briefly inserts the below-camera fallback on every activation.
        if resetGeometry {
            geometry.compactSideRoom = nil
            if !expanded, captureControls == nil { refreshPresentation(animated: false) }
        }
        readMenuSpace()
    }

    private func readMenuSpace() {
        guard menuSpaceTimer != nil, !menuSpaceReading,
              let app = NSWorkspace.shared.frontmostApplication else { return }
        menuSpaceReading = true
        let generation = menuSpaceGeneration
        let geometry = geometry
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? geometry.screen.maxY
        let window = panel?.windowNumber ?? -1
        let pid = app.processIdentifier
        menuSpaceQueue.async { [weak self] in
            let room = NotchMenuBarSpace.measure(pid: pid, geometry: geometry,
                                                primaryTop: primaryTop, ownWindow: window)
            DispatchQueue.main.async {
                guard let self else { return }
                self.menuSpaceReading = false
                guard self.menuSpaceTimer != nil else { return }
                guard self.menuSpaceGeneration == generation,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                    self.readMenuSpace(); return
                }
                if self.geometry.compactSideRoom != room {
                    let previousSize = self.surfaceSize
                    let grows = (room ?? 0) > (self.geometry.compactSideRoom ?? 0)
                    self.geometry.compactSideRoom = room
                    // Shrink immediately to protect new menus. Growing into
                    // confirmed free room can retain the normal smooth motion.
                    if previousSize != self.surfaceSize || self.panel?.isVisible != true {
                        self.refreshPresentation(animated: grows)
                    }
                }
            }
        }
    }

    private func updateScreen() {
        let screens = NSScreen.screens
        let builtIn = screens.map { CGDisplayIsBuiltin($0.notchDisplayID) != 0 }
        let index = NotchSupport.screenIndex(
            preference: NotchDisplay(rawValue: UserDefaults.standard.string(
                forKey: DefaultsKey.notchDisplay) ?? "") ?? .automatic,
            builtIn: builtIn, notched: screens.map { $0.safeAreaInsets.top > 0 },
            main: screens.firstIndex(where: { $0 === NSScreen.withMenuBar }) ?? 0)
        guard let index else { tearDownPresentation(); return }
        let screen = screens[index]
        let cameraWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            cameraWidth = max(0, right.minX - left.maxX)
        } else { cameraWidth = 0 }
        let next = NotchGeometry(screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
                                 cameraWidth: cameraWidth,
                                 layout: NotchSize(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.notchSize) ?? "") ?? .compact,
                                 menuBarHeight: NSStatusBar.system.thickness,
                                 compactSideRoom: screen.frame == geometry.screen ? geometry.compactSideRoom : nil,
                                 customWidth: UserDefaults.standard.double(forKey: DefaultsKey.notchCustomWidth),
                                 customHeight: UserDefaults.standard.double(forKey: DefaultsKey.notchCustomHeight))
        if next != geometry { menuSpaceGeneration += 1; geometry = next }
        if windowHost == nil {
            windowHost = NotchWindowHost(content: AnyView(NotchView(service: self)), geometry: presentationGeometry, size: surfaceSize)
            panel?.title = FeatureStrings.notch(L10n.shared.language).title
        }
        if modules.contains(.files), AppFeature.shelf.isAvailable {
            windowHost?.setFileDropActions(NotchFileDropActions(
                canAccept: { [weak self] pasteboard in
                    self?.canAcceptFileDrop == true && !ShelfService.shared.isInternalDragActive
                        && ShelfService.shared.canAcceptPasteboard(pasteboard)
                },
                enter: { [weak self] in self?.open(.files, takeFocus: false) },
                accept: { [weak self] in self?.accept($0) == true },
                exit: { [weak self] in
                    guard let self else { return }
                    self.hover(self.windowHost?.contains(NSEvent.mouseLocation) == true)
                }))
        } else { windowHost?.setFileDropActions(nil) }
        panel?.sharingType = NotchSupport.showsInCaptures() ? .readOnly : .none
    }

    private func installObservers() {
        observe(.default, NSMenu.didBeginTrackingNotification) { [weak self] in self?.trackingMenu = true; self?.hoverWork?.cancel() }
        observe(.default, NSMenu.didEndTrackingNotification) { [weak self] in
            guard let self else { return }
            self.trackingMenu = false
            self.hover(self.windowHost?.contains(NSEvent.mouseLocation) == true)
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            guard let self, !self.suspended else { return }
            self.invalidateMenuSpace(resetGeometry: true)
            self.syncWithPreferences()
        }
        observe(.default, UserDefaults.didChangeNotification) { [weak self] in
            // AppStorage can notify during a view update; defer any window work.
            DispatchQueue.main.async { self?.syncWithPreferences() }
        }
        observe(.default, .menuPanelWillShow) { [weak self] in self?.collapse() }
        session.onConsole = SessionActivity.shared.isActive
        session.locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] in
            guard let self, !self.suspended else { return }
            self.invalidateMenuSpace()
            let identifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            guard identifier != Bundle.main.bundleIdentifier, identifier != AssistiveKeyboard.bundleID else { return }
            self.panel?.resignKey()
            if self.expanded, self.modules.contains(.clipboard) {
                ClipboardHistoryService.shared.rememberPasteTarget()
            }
            if self.expanded, !self.pinned, !self.keepsWorkingSurface, self.captureControls == nil { self.collapse() }
        }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in
            self?.updateSession { $0.sleeping = true }
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in
            self?.updateSession { $0.sleeping = false }
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.updateSession { $0.displaysSleeping = true }
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.updateSession { $0.displaysSleeping = false }
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            self?.updateSession { $0.onConsole = false }
        }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.updateSession { $0.onConsole = true }
        }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.updateSession { $0.locked = true }
        }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            self?.updateSession { $0.locked = false }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observers.append((center, token))
    }

    private func updateSession(_ change: (inout NotchSessionState) -> Void) {
        guard running else { return }
        let couldPresent = session.canPresent
        change(&session)
        guard couldPresent != session.canPresent else { return }
        if session.canPresent {
            syncWithPreferences()
        } else {
            let cancel = captureControlsCancel
            endCaptureControls()
            cancel?()
            captureClose?()
            clearCapture()
            tearDownPresentation()
            if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
        }
    }

    private func installEventMonitors() {
        guard eventMonitors.isEmpty else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let token = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            guard let self, !self.keepsWorkingSurface,
                  !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) else { return }
            self.collapse()
        }) { eventMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown), handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.window === self.panel, self.selected == .tools, !self.showingAppPanel {
                return QuickLauncherService.shared.handlePanelKey(event, columns: NotchSupport.toolColumns)
            }
            if event.type == .keyDown, event.window === self.panel, event.keyCode == 53 {
                self.collapse()
                return nil
            }
            if clicks.contains(NSEvent.EventTypeMask(rawValue: 1 << event.type.rawValue)),
               event.window !== self.panel, !self.keepsWorkingSurface,
               !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) { self.collapse() }
            return event
        }) { eventMonitors.append(token) }
    }

    private func syncGestures() {
        guard NotchGestureSupport.isEnabled() else {
            panel?.handleScroll = nil
            gesture = NotchGestureSupport()
            return
        }
        panel?.handleScroll = { [weak self] event in self?.handleGesture(event) ?? false }
    }

    private func handleGesture(_ event: NSEvent) -> Bool {
        guard running, !suspended, NotchGestureSupport.isEnabled(), let panel,
              !trackingMenu, captureControls == nil, !heldDrag,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            gesture = NotchGestureSupport()
            return false
        }
        let screenPoint = panel.convertPoint(toScreen: event.locationInWindow)
        guard windowHost?.contains(screenPoint) == true else { gesture = NotchGestureSupport(); return false }
        let fromTop = panel.frame.maxY - screenPoint.y
        let inHeader = NotchSupport.gestureIsOverHeader(expanded: expanded, peeking: peeking,
                                                       fromTop: fromTop, safeTop: geometry.safeContentTop)
        var inNativeControl = false
        var inScrollView = false
        var view = panel.contentView?.hitTest(event.locationInWindow)
        while let current = view {
            if current is NSControl || current is NSTextView { inNativeControl = true }
            if current is NSScrollView { inScrollView = true }
            view = current.superview
        }
        let musicSurface = modules.contains(.music)
            && (compactMusicIsVisible || (expanded && selected == .music && !showingAppPanel))
        let vertical = !inNativeControl && (!expanded || inHeader)
        let horizontal = !inNativeControl && !inScrollView && !inHeader && musicSurface
        let x = NotchGestureSupport.movement(Double(event.scrollingDeltaX), precise: event.hasPreciseScrollingDeltas,
                                             inverted: event.isDirectionInvertedFromDevice)
        let y = NotchGestureSupport.movement(Double(event.scrollingDeltaY), precise: event.hasPreciseScrollingDeltas,
                                             inverted: event.isDirectionInvertedFromDevice)
        guard let action = gesture.handle(x: x, y: y, timestamp: event.timestamp,
                                          began: event.phase.contains(.began),
                                          ended: !event.phase.intersection([.ended, .cancelled]).isEmpty,
                                          momentum: !event.momentumPhase.isEmpty,
                                          precise: event.hasPreciseScrollingDeltas,
                                          hasPhase: !event.phase.isEmpty,
                                          allowVertical: vertical, allowHorizontal: horizontal, expanded: expanded) else { return false }
        switch action {
        case .open: open()
        case .close: collapse()
        case .nextTrack, .previousTrack:
            guard musicSurface else { gesture = NotchGestureSupport(); return false }
            NotchMusicService.shared.send(action == .nextTrack ? .next : .previous)
        }
        return true
    }

    private func removeEventMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    private func bindEvents() {
        subscriptions.removeAll()
        if modules.contains(.timer) {
            NotchTimerService.shared.$session.removeDuplicates().receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if modules.contains(.music) {
            NotchMusicService.shared.$playback.map { ($0 != nil, $0?.isPlaying == true) }
                .removeDuplicates { $0 == $1 }.receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if NotchSupport.routes(.download) {
            NotchDownloadService.shared.$items.receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.syncMenuSpaceMonitoring()
                self?.objectWillChange.send()
                self?.refreshPresentation()
            }.store(in: &subscriptions)
            NotchDownloadService.shared.onArrival = { [weak self] item in
                self?.show(NotchNotice(event: .download,
                    title: FeatureStrings.notchFiles(L10n.shared.language).completed,
                    detail: item.name, symbol: "arrow.down.circle.fill"))
            }
        }
        stopPower()
        if NotchSupport.routes(.volume) {
            let mixer = AppVolumeMixer.shared
            volumeBaseline = mixer.systemOutputVolume
            muteBaseline = mixer.systemOutputMuted
            mixer.$systemOutputVolume.combineLatest(mixer.$systemOutputMuted)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] volume, muted in self?.volumeChanged(volume, muted: muted) }
                .store(in: &subscriptions)
        }
        if NotchSupport.routes(.systemNotification) {
            NotchNotificationService.shared.received.sink { [weak self] item in
                guard let self else { return }
                let shown = self.show(NotchNotice(event: .systemNotification, title: item.content.title,
                                                 detail: item.content.body, symbol: "bell.fill", notification: item.content, notificationID: item.id))
                if shown, !self.expanded, self.captureControls == nil, !self.dragPlaceholder {
                    NotchNotificationService.shared.closeNative(item.id)
                }
            }.store(in: &subscriptions)
        }
        if NotchSupport.routes(.clipboard) {
            let history = ClipboardHistoryService.shared
            history.capturedEntry.receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self else { return }
                let text = FeatureStrings.clipboard(L10n.shared.language)
                self.show(NotchNotice(event: .clipboard, title: text.copied,
                                      detail: text.title, symbol: "doc.on.clipboard"))
            }.store(in: &subscriptions)
        }
        if NotchSupport.routes(.battery) || idleContent == .battery { startPower() }
    }

    func showCurrentVolume() {
        let mixer = AppVolumeMixer.shared
        guard let volume = mixer.systemOutputVolume else { return }
        showVolume(volume, muted: mixer.systemOutputMuted)
    }

    private func volumeChanged(_ volume: Double?, muted: Bool?) {
        defer { volumeBaseline = volume; muteBaseline = muted }
        guard let volume, volumeBaseline != nil,
              volume != volumeBaseline || (muteBaseline != nil && muted != muteBaseline) else { return }
        showVolume(volume, muted: muted)
    }

    private func showVolume(_ volume: Double, muted: Bool?) {
        // The open panel already shows the adjustment. Do not retain a notice
        // behind it that would appear only after the pointer leaves.
        guard volume.isFinite, !expanded else { return }
        let value = muted == true ? 0 : min(1, max(0, volume))
        show(NotchNotice(event: .volume, title: FeatureStrings.notch(L10n.shared.language).volume,
                         detail: "\(Int((value * 100).rounded()))%",
                         symbol: value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", level: value))
    }

    private func startPower() {
        guard PowerSampler.hasInternalBattery else { return }
        powerSampler = PowerSampler(smc: nil)
        power = powerSampler?.sample() ?? PowerReading()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let owner = Unmanaged<NotchService>.fromOpaque(context).takeUnretainedValue()
            owner.powerChanged()
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    private func stopPower() {
        if let source = powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        powerSource = nil
        powerSampler = nil
    }

    private func powerChanged() {
        guard running, !suspended, let sampler = powerSampler else { return }
        let before = power
        let next = sampler.sample()
        power = next
        let low = (next.chargePercent ?? 100) <= 20 && (before.chargePercent ?? 0) > 20
        guard before.externalConnected != next.externalConnected || low
                || (before.isCharging && !next.isCharging && next.chargePercent == 100) else { return }
        let text = FeatureStrings.notch(L10n.shared.language)
        let title = low ? text.lowBattery : next.externalConnected
            ? (next.isCharging ? text.charging : next.chargePercent == 100
                ? text.charged : L10n.shared.s.powerPluggedIn) : text.onBattery
        show(NotchNotice(event: .battery, title: title,
                         detail: next.chargePercent.map { "\($0)%" } ?? "",
                         symbol: next.externalConnected ? "battery.100percent.bolt" : "battery.25percent"))
    }

    private func syncVisibleConsumers() {
        syncMenuSpaceMonitoring()
        guard running, !suspended else { releaseMonitor(); return }
        if !NotchCameraSupport.canPresent(expanded: expanded, selected: selected,
            appPanel: showingAppPanel, captureControls: captureControls != nil) {
            CameraPreviewService.shared.hideEmbedded()
        }
        let musicWanted = modules.contains(.music) && ((expanded && selected == .music && !showingAppPanel)
            || NotchSupport.idleContent() == .music || NotchSupport.watchesMusicActivity())
        if musicWanted { NotchMusicService.shared.start() } else { NotchMusicService.shared.stop() }
        let needs = expanded && selected == .system && selectedMetric == nil && modules.contains(.system) && !showingAppPanel
        var detailNeeds = expanded ? selectedMetric?.monitorNeeds ?? .none : .none
        if needs, AppFeature.monitorDisk.isAvailable { detailNeeds.disk = true }
        SystemMonitor.shared.setNotchDetailNeeds(detailNeeds)
        if needs != notchNeedsMonitor {
            notchNeedsMonitor = needs
            SystemMonitor.shared.setNotchVisible(needs)
        }
    }

    private func releaseMonitor() {
        SystemMonitor.shared.setNotchDetailNeeds(.none)
        guard notchNeedsMonitor else { return }
        notchNeedsMonitor = false
        SystemMonitor.shared.setNotchVisible(false)
    }
}

extension NSScreen {
    var notchDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
