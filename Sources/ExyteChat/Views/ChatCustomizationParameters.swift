//
//  ChatCustomizationParameters.swift
//  Chat
//
//  Created by Alisa Mylnikova on 02.04.2026.
//

import SwiftUI

struct ChatCustomizationParameters {
    var isListAboveInputView: Bool = true
    var showScrollToBottomButton: Bool = true
    var showNetworkConnectionProblem: Bool = false
    var showDateHeaders: Bool = true
    var isScrollEnabled: Bool = true
    var autoFocusTextInputOnChatOpen: Bool = false
    var showMessageMenuOnLongPress: Bool = true
    var showShareAttachmentButton: Bool = true
    var showLastReadIndicator: Bool = false
    var keyboardDismissMode: ScrollDismissesKeyboardMode = .never
    var messageMenuAnimationDuration: CGFloat = 0.3
    var contentInsets = EdgeInsets()

    var scrollToParams: ScrollToParams?
    var onContentOffsetChange: ((CGFloat) -> Void)? // Internal → External
    var onMessageAppear: ((Message) -> Void)?
    var onTransactionReady: ((ChatUpdateTransaction) -> Void)?
    var onLiveLocationBroadcast: ((LiveLocationBroadcastEvent) -> Void)?

    var olderMessagesPaginationHandler: PaginationHandler?
    var newerMessagesPaginationHandler: PaginationHandler?
    var localization = ChatLocalization.defaultLocalization // these can be localized in the Localizable.strings files
    var reactionDelegate: ReactionDelegate?
    var listSwipeActions = ListSwipeActions()
}

public enum ChatScrollPosition: Equatable, Sendable {
    case top
    case middle
    case bottom
}

public struct ScrollToParams: Equatable {
    public enum ScrollTo: Equatable {
        case messageID(messageID: String, position: ChatScrollPosition, offset: CGFloat)
        case contentOffset(CGFloat)
        case newestMessage
        case oldestMessage
    }

    let scrollTo: ScrollTo

    public init(messageID: String, position: ChatScrollPosition = .middle, offset: CGFloat = 0) {
        self.scrollTo = .messageID(messageID: messageID, position: position, offset: offset)
    }

    public init(offset: CGFloat) {
        self.scrollTo = .contentOffset(offset)
    }

    public init(_ scrollTo: ScrollTo) {
        self.scrollTo = scrollTo
    }
}

struct MessageCustomizationParameters {
    var showTimeView = true
    var showUsername = false
    var linkPreviewLimit = 1
    var shouldShowPreviewForLink: (URL) -> Bool = { _ in true }
    var font = Font.body
    var timeFont = Font.caption

    // avatar
    var showAvatar = true
    var avatarSize: CGFloat = 32
    var tapAvatarClosure: ChatView.TapAvatarClosure?
    var avatarBuilder: ((User)->(AnyView))?
}

struct InputViewCustomizationParameters {
    var externalInputText: String? // External → Internal
    var onInputTextChange: ((String) -> Void)? // Internal → External
    var availableInputs: [AvailableInputType] = [.text, .audio, .media]
    var recorderSettings = RecorderSettings()
    var audioRecordingMode: AudioRecordingMode = .holdToRecord
    var photoPickerSelectionLimit: Int? = nil
}
