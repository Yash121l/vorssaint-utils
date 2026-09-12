// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchFilesView: View {
    let service: NotchService
    @ObservedObject private var shelf = ShelfService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var shareAnchor = ShelfSharePickerAnchor.Anchor()
    @State private var confirmingClear = false

    var body: some View {
        VStack(spacing: 12) {
            if shelf.items.isEmpty {
                NotchEmptyView(symbol: "tray.and.arrow.down", message: FeatureStrings.notch(l10n.language).dropHint)
                    .frame(maxHeight: .infinity)
                    .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 0.75, dash: [4, 5])) }
            } else {
                ShelfTilesView(items: shelf.visibleItems,
                               contentRevision: shelf.contentRevision,
                               selection: shelf.selection,
                               expandedBatches: shelf.expandedBatches,
                               revealID: shelf.revealTargetID,
                               revealSerial: shelf.addSerial)
                    .frame(maxHeight: .infinity)
                HStack {
                    Text(l10n.s.shelfHint).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    NotchIconButton(symbol: "square.and.arrow.up", title: l10n.s.shelfActionShare) {
                        service.pinned = true
                        shareAnchor.present(shelf.fileURLsForActions())
                    }
                    .background(ShelfSharePickerAnchor(anchor: shareAnchor))
                    .disabled(!shelf.hasFilesForActions)
                    NotchIconButton(symbol: "trash", title: l10n.s.shelfClearAll) { confirmingClear = true }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(l10n.s.shelfClearAll, isPresented: $confirmingClear, titleVisibility: .visible) {
            Button(l10n.s.shelfClearAll, role: .destructive) { shelf.clear() }
            Button(l10n.s.uninstallerCancel, role: .cancel) {}
        }
    }
}
