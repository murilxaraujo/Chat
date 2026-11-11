//
//  InputView+AttachMenu.swift
//  Chat
//

import SwiftUI
import UIKit

private struct AttachMenuItem {
    let icon: Image
    let title: String
    let action: InputViewAction
}

extension InputView {

    fileprivate var attachMenuItems: [AttachMenuItem] {
        var items: [AttachMenuItem] = []
        if isMediaAvailable() {
            items.append(AttachMenuItem(icon: theme.images.inputView.attach, title: localization.attachMediaText, action: .photo))
            items.append(AttachMenuItem(icon: theme.images.inputView.attachCamera, title: localization.attachCameraText, action: .camera))
        }
        if isDocumentAvailable() {
            items.append(AttachMenuItem(icon: theme.images.attachMenu.document, title: localization.attachDocumentText, action: .document))
        }
        if isLocationAvailable() {
            items.append(AttachMenuItem(icon: theme.images.attachMenu.location, title: localization.attachLocationText, action: .location))
        }
        return items
    }

    @ViewBuilder
    var leftButton: some View {
        let items = attachMenuItems

        if items.count > 1 {
            attachMenuButton(items: items)
        } else if let item = items.first, item.action == .photo {
            menuButton(action: .photo, image: theme.images.inputView.attach)
        } else if let item = items.first, item.action == .document {
            menuButton(action: .document, image: theme.images.attachMenu.document)
        } else if let item = items.first, item.action == .location {
            menuButton(action: .location, image: theme.images.attachMenu.location)
        }
    }

    fileprivate func attachMenuContent(_ items: [AttachMenuItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                AttachMenuRow(icon: item.icon, title: item.title) {
                    onAction(item.action)
                    isAttachMenuPresented = false
                }
            }
        }
        .frame(minWidth: 220, alignment: .leading)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.colors.inputBG)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        )
    }

    fileprivate func attachMenuButton(items: [AttachMenuItem]) -> some View {
        Button {
            openAttachMenu()
        } label: {
            theme.images.inputView.attach
                .viewSize(24)
                .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 6))
        }
        .popover(
            isPresented: $isAttachMenuPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            attachMenuContent(items)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// Wait for the keyboard to dismiss so the popover anchors to the input bar's final frame.
    fileprivate func openAttachMenu() {
        guard keyboardState.isShown else {
            isAttachMenuPresented = true
            return
        }

        keyboardState.resignFirstResponder()
        Task {
            for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardDidHideNotification) {
                break
            }
            isAttachMenuPresented = true
        }
    }

    func menuButton(action: InputViewAction, image: Image) -> some View {
        Button {
            onAction(action)
        } label: {
            image
                .viewSize(24)
                .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 6))
        }
    }
}

private struct AttachMenuRow: View {
    @Environment(\.chatTheme) var theme

    let icon: Image
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 10) {
                icon
                    .sizeAndColor(20, theme.colors.mainTint)
                Text(title)
                    .font(.callout)
                    .foregroundColor(theme.colors.mainText)
            }
            .padding(14, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
