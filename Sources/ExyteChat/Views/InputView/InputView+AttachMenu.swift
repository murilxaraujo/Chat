//
//  InputView+AttachMenu.swift
//  Chat
//

import SwiftUI

private struct AttachMenuItem {
    let systemImage: String
    let title: String
    let action: InputViewAction
}

extension InputView {

    fileprivate var attachMenuItems: [AttachMenuItem] {
        var items: [AttachMenuItem] = []
        if isMediaAvailable() {
            items.append(AttachMenuItem(systemImage: "photo", title: localization.attachMediaText, action: .photo))
            items.append(AttachMenuItem(systemImage: "camera", title: localization.attachCameraText, action: .camera))
        }
        if isDocumentAvailable() {
            items.append(AttachMenuItem(systemImage: "doc", title: localization.attachDocumentText, action: .document))
        }
        if isLocationAvailable() {
            items.append(AttachMenuItem(systemImage: "location.fill", title: localization.attachLocationText, action: .location))
        }
        return items
    }

    @ViewBuilder
    var leftButton: some View {
        let items = attachMenuItems

        if items.count > 1 {
            attachMenuButton(items: items)
        } else if let item = items.first, item.action == .photo {
            menuButton(action: .photo, image: Image(systemName: "paperclip"))
        } else if let item = items.first, item.action == .document {
            menuButton(action: .document, image: Image(systemName: "doc"))
        } else if let item = items.first, item.action == .location {
            menuButton(action: .location, image: Image(systemName: "location.fill"))
        }
    }

    fileprivate func attachMenuButton(items: [AttachMenuItem]) -> some View {
        Menu {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button {
                    onAction(item.action)
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                }
            }
        } label: {
            Image(systemName: "paperclip")
                .viewSize(24)
                .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 6))
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
