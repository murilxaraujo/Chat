//
//  MessageMenu+Action.swift
//  Chat
//

import SwiftUI

public protocol MessageMenuAction: Equatable, CaseIterable {
    func title() -> String
    func icon() -> Image
    func isDestructive() -> Bool

    static func menuItems(for message: Message) -> [Self]
}

extension MessageMenuAction {
    public func isDestructive() -> Bool { false }

    public static func menuItems(for message: Message) -> [Self] {
        Self.allCases.map { $0 }
    }
}

public enum DefaultMessageMenuAction: MessageMenuAction, Sendable {

    case reply
    case edit(saveClosure: @Sendable (String) -> Void)
    case share

    public init() { self = .reply }

    public func title() -> String {
        switch self {
        case .reply:
            "Reply"
        case .edit:
            "Edit"
        case .share:
            "Share"
        }
    }

    public func icon() -> Image {
        switch self {
        case .reply:
            Image(systemName: "arrowshape.turn.up.left")
        case .edit:
            Image(systemName: "bubble.and.pencil")
        case .share:
            Image(systemName: "square.and.arrow.up")
        }
    }

    nonisolated public static func == (lhs: DefaultMessageMenuAction, rhs: DefaultMessageMenuAction) -> Bool {
        switch (lhs, rhs) {
        case (.reply, .reply),
             (.edit(_), .edit(_)),
             (.share, .share):
            return true
        default:
            return false
        }
    }

    public static let allCases: [DefaultMessageMenuAction] = [
        .reply, .edit(saveClosure: {_ in}), .share
    ]

    static public func menuItems(for message: Message) -> [DefaultMessageMenuAction] {
        var items: [DefaultMessageMenuAction] = message.user.isCurrentUser ? [.reply, .edit(saveClosure: {_ in})] : [.reply]
        let hasShareableAttachments = message.attachments.contains { $0.fullUploadStatus == nil || $0.fullUploadStatus == .complete }
        if hasShareableAttachments {
            items.append(.share)
        }
        return items
    }
}
