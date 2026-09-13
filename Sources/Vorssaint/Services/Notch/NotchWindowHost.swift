// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import QuartzCore

struct NotchFileDropActions {
    let canAccept: (NSPasteboard) -> Bool
    let enter: () -> Void
    let accept: (NSPasteboard) -> Bool
    let exit: () -> Void
}

enum NotchContentTransition { case none, reveal, dismiss, replace }

/// The window reserves the transition's bounds once. Core Animation moves
/// the silhouette independently of SwiftUI layout and the application run loop.
final class NotchWindowHost: NSObject, CAAnimationDelegate {
    let panel: NotchPanel
    private let canvas: NotchCanvas
    private var currentGeometry: NotchGeometry
    private var animationGeneration = 0
    private var isAnimating = false
    private var settledActions: [() -> Void] = []
    private(set) var targetSize: CGSize
    private(set) var resizeCount = 0

    init(content: AnyView, geometry: NotchGeometry, size: CGSize) {
        targetSize = size
        currentGeometry = geometry
        panel = NotchPanel(contentRect: geometry.frame(for: size),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        canvas = NotchCanvas(content: content, size: size, attached: geometry.isNotched)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary,
                                    .transient, .ignoresCycle]
        panel.contentView = canvas
        canvas.layoutSubtreeIfNeeded()
    }

    func present(size: CGSize, geometry: NotchGeometry, animated: Bool, transitionContent: NotchContentTransition = .none) {
        canvas.updateContrast()
        let frame = geometry.frame(for: size)
        let changesFrame = geometry.isNotched != currentGeometry.isNotched || size != targetSize
            || frame != currentGeometry.frame(for: targetSize) || (!isAnimating && panel.frame != frame)
        guard changesFrame || transitionContent != .none else {
            currentGeometry = geometry
            return
        }
        let canAnimate = animated && panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if canAnimate { canvas.transitionContent(transitionContent) }
        else { canvas.restoreContent() }
        guard changesFrame else { return }
        let previousPath = canvas.visiblePath
        let previousWidth = canvas.bounds.width
        let sameScreen = geometry.screen == currentGeometry.screen && geometry.isNotched == currentGeometry.isNotched
            && geometry.topInset == currentGeometry.topInset
        animationGeneration += 1
        isAnimating = false
        canvas.stopMotion()
        targetSize = size
        currentGeometry = geometry
        resizeCount += 1
        guard canAnimate, sameScreen, let previousPath else {
            settle()
            return
        }

        let envelope = NotchMotion.envelope(from: panel.frame.size, to: size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.setContentSize(size, attached: geometry.isNotched)
        panel.setFrame(geometry.frame(for: envelope), display: false)
        canvas.layoutSubtreeIfNeeded()
        var translation = CGAffineTransform(translationX: (envelope.width - previousWidth) / 2, y: 0)
        let from = previousPath.copy(using: &translation)
        let duration = NotchMotion.duration(from: previousPath.boundingBoxOfPath.size, to: size)
        let animation = CASpringAnimation(perceptualDuration: duration, bounce: 0)
        animation.keyPath = "path"
        animation.fromValue = from
        animation.toValue = canvas.targetPath
        animation.duration = animation.settlingDuration
        animation.delegate = self
        animation.setValue(animationGeneration, forKey: "notchGeneration")
        isAnimating = true
        canvas.animate(animation)
        CATransaction.commit()
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        guard flag, isAnimating, anim.value(forKey: "notchGeneration") as? Int == animationGeneration else { return }
        settle()
    }

    private func settle() {
        isAnimating = false
        canvas.stopMotion()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.setContentSize(targetSize, attached: currentGeometry.isNotched)
        panel.setFrame(currentGeometry.frame(for: targetSize), display: false)
        canvas.layoutSubtreeIfNeeded()
        CATransaction.commit()
        runSettledActions()
    }

    func whenSettled(_ action: @escaping () -> Void) {
        settledActions.append(action)
        if !isAnimating { runSettledActions() }
    }

    private func runSettledActions() {
        let actions = settledActions
        settledActions.removeAll()
        for action in actions { DispatchQueue.main.async(execute: action) }
    }

    var visibleFrame: CGRect {
        currentGeometry.frame(for: canvas.visiblePath?.boundingBoxOfPath.size ?? targetSize)
    }

    func contains(_ screenPoint: CGPoint) -> Bool {
        guard panel.isVisible else { return false }
        let local = canvas.convert(panel.convertPoint(fromScreen: screenPoint), from: nil)
        return canvas.containsVisiblePoint(local)
    }

    func setFileDropActions(_ actions: NotchFileDropActions?) { canvas.setFileDropActions(actions) }

#if VORSSAINT_DEVELOPMENT
    func beginProbeDrop(_ pasteboard: NSPasteboard, localSource: Bool = false) -> NSDragOperation {
        canvas.beginDrop(pasteboard, localSource: localSource)
    }
    func finishProbeDrop(_ pasteboard: NSPasteboard) -> Bool { canvas.finishDrop(pasteboard) }
#endif

    var contentCanvasSize: CGSize { canvas.hostedSize }

    var contentTopOnScreen: CGFloat {
        panel.convertPoint(toScreen: canvas.contentTopInWindow).y
    }

    func close() {
        animationGeneration += 1
        isAnimating = false
        canvas.stopMotion()
        panel.orderOut(nil)
        panel.contentView = nil
        runSettledActions()
    }
}

final class NotchPanel: NSPanel {
    var acceptsKeyFocus = false
    var handleScroll: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { acceptsKeyFocus }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel, handleScroll?(event) == true { return }
        super.sendEvent(event)
    }
}

private final class NotchCanvas: NSView {
    private let host: NotchHostingView
    private let silhouette = CAShapeLayer()
    private let edge = CAShapeLayer()
    private let contentCover = CALayer()
    private var dropActions: NotchFileDropActions?
    private var acceptingDrag = false
    private var contentSize: CGSize
    private var attached: Bool
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    init(content: AnyView, size: CGSize, attached: Bool) {
        contentSize = size
        self.attached = attached
        host = NotchHostingView(rootView: content)
        host.sizingOptions = []
        host.wantsLayer = true
        host.autoresizingMask = []
        super.init(frame: CGRect(origin: .zero, size: size))
        autoresizesSubviews = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        layer?.mask = silhouette
        addSubview(host)
        edge.fillColor = nil
        updateContrast()
        edge.lineWidth = 0.5
        edge.zPosition = 2
        layer?.addSublayer(edge)
        contentCover.name = "notch.contentCover"
        contentCover.backgroundColor = NSColor.black.cgColor
        contentCover.opacity = 0
        contentCover.zPosition = 1
        layer?.addSublayer(contentCover)
        setContentSize(size, attached: attached)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setContentSize(_ size: CGSize, attached: Bool) {
        contentSize = size
        self.attached = attached
        needsLayout = true
    }

    func updateContrast() {
        let color = NSColor.white.withAlphaComponent(
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.45 : 0.12).cgColor
        guard edge.strokeColor != color else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edge.strokeColor = color
        CATransaction.commit()
    }

    func setFileDropActions(_ actions: NotchFileDropActions?) {
        let wasEnabled = dropActions != nil
        dropActions = actions
        guard wasEnabled != (actions != nil) else { return }
        unregisterDraggedTypes()
        if actions != nil { registerForDraggedTypes(ShelfService.tileDropTypes) }
        else { acceptingDrag = false }
    }

    func beginDrop(_ pasteboard: NSPasteboard, localSource: Bool) -> NSDragOperation {
        // In-app tile drags keep their own reorder/merge destinations. This
        // stable native view receives external drops while its content expands.
        acceptingDrag = !localSource && dropActions?.canAccept(pasteboard) == true
        if acceptingDrag { dropActions?.enter() }
        return acceptingDrag ? .copy : []
    }

    func finishDrop(_ pasteboard: NSPasteboard) -> Bool {
        defer { acceptingDrag = false }
        return acceptingDrag && dropActions?.accept(pasteboard) == true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard containsVisiblePoint(convert(sender.draggingLocation, from: nil)) else {
            if acceptingDrag { acceptingDrag = false; dropActions?.exit() }
            return []
        }
        return acceptingDrag ? .copy : beginDrop(sender.draggingPasteboard, localSource: sender.draggingSource != nil)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        acceptingDrag = false
        dropActions?.exit()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard containsVisiblePoint(convert(sender.draggingLocation, from: nil)) else {
            acceptingDrag = false
            return false
        }
        return finishDrop(sender.draggingPasteboard)
    }

    var hostedSize: CGSize { host.frame.size }
    var contentTopInWindow: CGPoint { host.convert(.zero, to: nil) }

    private static let motionKey = "notch.resize"
    var targetPath: CGPath? { silhouette.path }
    var visiblePath: CGPath? { silhouette.presentation()?.path ?? silhouette.path }

    func containsVisiblePoint(_ point: CGPoint) -> Bool { visiblePath?.contains(point) == true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard containsVisiblePoint(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }

    func animate(_ animation: CAAnimation) {
        silhouette.add(animation, forKey: Self.motionKey)
        if let borderAnimation = animation.copy() as? CAAnimation {
            borderAnimation.delegate = nil
            edge.add(borderAnimation, forKey: Self.motionKey)
        }
    }
    func stopMotion() {
        silhouette.removeAnimation(forKey: Self.motionKey)
        edge.removeAnimation(forKey: Self.motionKey)
    }

    func transitionContent(_ kind: NotchContentTransition) {
        guard kind != .none else { return }
        let currentOpacity = contentCover.presentation()?.opacity ?? contentCover.opacity
        contentCover.removeAnimation(forKey: "notch.opacity")
        host.layer?.removeAnimation(forKey: kCATransition)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if kind == .replace {
            contentCover.opacity = 0
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.18
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            host.layer?.add(transition, forKey: kCATransition)
        } else {
            // Fade the pixels, not the hosting view: making that view
            // transparent also removes the compact button's AX/hit frame.
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            let start: Float = kind == .dismiss || currentOpacity == 0 ? 1 : currentOpacity
            // Give the silhouette a head start before revealing full-width
            // content. Reversals continue from the opacity already on screen.
            animation.values = [start, start, 0]
            animation.keyTimes = kind == .dismiss ? [0, 0.65, 1] : [0, 0.625, 1]
            animation.duration = 0.40
            animation.calculationMode = .linear
            animation.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut)]
            contentCover.opacity = 0
            contentCover.add(animation, forKey: "notch.opacity")
        }
        CATransaction.commit()
    }

    func restoreContent() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentCover.removeAnimation(forKey: "notch.opacity")
        contentCover.opacity = 0
        host.layer?.removeAnimation(forKey: kCATransition)
        CATransaction.commit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        silhouette.frame = bounds
        edge.frame = bounds
        contentCover.frame = bounds
        var translation = CGAffineTransform(translationX: (bounds.width - contentSize.width) / 2, y: 0)
        silhouette.path = NotchShape(attached: attached, radius: min(28, contentSize.height / 2))
            .path(in: CGRect(origin: .zero, size: contentSize)).cgPath.copy(using: &translation)
        edge.path = silhouette.path
        edge.opacity = contentSize.height > 64 ? 1 : 0
        // Render the entire reveal area once; changing only the layer mask
        // then exposes cached pixels without redrawing SwiftUI every frame.
        if host.frame != bounds { host.frame = bounds }
        CATransaction.commit()
    }
}

private final class NotchHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
