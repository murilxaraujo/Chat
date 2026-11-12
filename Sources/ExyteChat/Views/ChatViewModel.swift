//
//  Created by Alex.M on 20.06.2022.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ChatViewModel {

    private(set) var fullscreenAttachmentItem: Optional<Attachment> = nil
    var fullscreenAttachmentPresented = false

    private(set) var fullscreenLocationMessageId: String? = nil
    var fullscreenLocationPresented = false

    var shareAttachmentsItem: ShareAttachmentsItem? = nil
    private(set) var isPreparingAttachmentsShare = false

    var messageMenuRow: MessageRow?
    
    /// The messages frame that is currently being rendered in the Message Menu
    /// - Note: Used to further refine a messages frame (instead of using the cell boundary), mainly used for positioning reactions
    var messageFrame: CGRect = .zero

    /// Transient visible-row geometry. These values intentionally do not publish changes while scrolling.
    @ObservationIgnored var visibleMessageFrames: [String: CGRect] = [:]
    @ObservationIgnored
    var messageCellFrame: CGRect = .zero
    
    /// Provides a mechanism to issue haptic feedback to the user
    /// - Note: Used when launching the MessageMenu
    
    let inputFieldId = UUID()
    let messageRecordingPlayer = RecordingPlayer()

    @ObservationIgnored var didSendMessage: (DraftMessage) -> Void = {_ in }
    @ObservationIgnored var didUpdateAttachmentStatus: (AttachmentUploadUpdate) -> Void = { _ in }
    @ObservationIgnored
    var inputViewModel: InputViewModel?
    @ObservationIgnored
    var globalFocusState: GlobalFocusState?
    @ObservationIgnored private var attachmentShareTask: Task<Void, Never>?

    deinit {
        attachmentShareTask?.cancel()
    }

    let liveLocationBroadcaster = LiveLocationBroadcaster()
    func startLiveLocationSharing(messageId: String, liveLocation: LiveLocation) {
        liveLocationBroadcaster.start(messageId: messageId, startedAt: liveLocation.startedAt, expiresAt: liveLocation.expiresAt)
    }

    func stopLiveLocationSharing() {
        liveLocationBroadcaster.finish()
    }

    func presentAttachmentFullScreen(_ attachment: Attachment) {
        fullscreenAttachmentItem = attachment
        fullscreenAttachmentPresented = true
    }
    
    func dismissAttachmentFullScreen() {
        fullscreenAttachmentPresented = false
        fullscreenAttachmentItem = nil
    }

    func presentFullscreenLocation(_ messageId: String) {
        fullscreenLocationMessageId = messageId
        fullscreenLocationPresented = true
    }

    func dismissFullscreenLocation() {
        fullscreenLocationMessageId = nil
        fullscreenLocationPresented = false
    }

    func shareAttachments(_ attachments: [Attachment]) {
        guard !attachments.isEmpty, !isPreparingAttachmentsShare else { return }
        isPreparingAttachmentsShare = true
        attachmentShareTask?.cancel()
        attachmentShareTask = Task { @MainActor [weak self] in
            let urls = await AttachmentSharing.prepareForSharing(attachments)
            guard let self, !Task.isCancelled else { return }
            self.isPreparingAttachmentsShare = false
            if !urls.isEmpty {
                self.shareAttachmentsItem = ShareAttachmentsItem(urls: urls)
            }
            self.attachmentShareTask = nil
        }
    }
    
    func updateAttachmentStatus(_ uploadUpdate: AttachmentUploadUpdate) {
        didUpdateAttachmentStatus(uploadUpdate)
    }

    func sendMessage(_ message: DraftMessage) {
        didSendMessage(message)
    }

    func showMessageMenu(for row: MessageRow) {
        messageCellFrame = visibleMessageFrames[row.id] ?? .zero
        messageMenuRow = row
    }

    func messageMenuAction() -> (Message, DefaultMessageMenuAction) -> Void {
        { [weak self] message, action in
            self?.messageMenuActionInternal(message: message, action: action)
        }
    }

    func focusTheInputTextView() {
        globalFocusState?.focus = .uuid(inputFieldId)
    }

    func messageMenuActionInternal(message: Message, action: DefaultMessageMenuAction) {
        switch action {
        case .reply:
            withAnimation(.easeInOut(duration: 0.2)) {
                inputViewModel?.attachments.replyMessage = message.toReplyMessage()
            }
            focusTheInputTextView()
        case .edit(let saveClosure):
            inputViewModel?.text = String(message.attributedText.characters)
            inputViewModel?.edit(saveClosure)
            focusTheInputTextView()
        case .share:
            let shareableAttachments = message.attachments.filter { $0.fullUploadStatus == nil || $0.fullUploadStatus == .complete }
            shareAttachments(shareableAttachments)
        }
    }
}

struct ShareAttachmentsItem: Identifiable {
    let id = UUID()
    let urls: [URL]
}
