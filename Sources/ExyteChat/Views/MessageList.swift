import SwiftUI

private struct MessageFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ScrollMetrics: Equatable {
    var contentOffset: CGFloat = 0
    var contentHeight: CGFloat = 0
    var viewportHeight: CGFloat = 0
    var visibleMinY: CGFloat = 0
    var visibleMaxY: CGFloat = 0

    var distanceFromTop: CGFloat { max(0, visibleMinY) }
    var distanceFromBottom: CGFloat { max(0, contentHeight - visibleMaxY) }
}

struct ChatMessageList<MessageContent: View>: View {
    typealias MessageBuilderParamsClosure = ChatView<MessageContent, InputView, DefaultMessageMenuAction>.MessageBuilderParamsClosure


    @ObservedObject var viewModel: ChatViewModel
    @Binding var pendingScrollTo: ScrollToParams?
    @Binding var isScrolledToBottom: Bool

    let messageBuilder: MessageBuilderParamsClosure
    let mainHeaderBuilder: (() -> AnyView)?
    let dateHeaderBuilder: ((Date) -> AnyView)?
    let type: ChatType
    let sections: [MessagesSection]
    let chatParams: ChatCustomizationParameters
    let messageParams: MessageCustomizationParameters

    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @State private var scrollMetrics = ScrollMetrics()
    @State private var messageFrames: [String: CGRect] = [:]
    @State private var offsetAdjustment: OffsetAdjustment?
    @StateObject private var paginationState = PaginationState()
    @State private var transaction = ChatUpdateTransaction()

    private struct OffsetAdjustment {
        let messageID: String
        let position: ChatScrollPosition
        let offset: CGFloat
    }

    private var displayedSections: [MessagesSection] {
        type == .conversation ? Array(sections.reversed()) : sections
    }

    private var displayedRows: [MessageRow] {
        displayedSections.flatMap { section in
            type == .conversation ? Array(section.rows.reversed()) : section.rows
        }
    }

    private var topPaginationHandler: PaginationHandler? {
        type == .conversation
            ? chatParams.olderMessagesPaginationHandler
            : chatParams.newerMessagesPaginationHandler
    }

    private var bottomPaginationHandler: PaginationHandler? {
        type == .conversation
            ? chatParams.newerMessagesPaginationHandler
            : chatParams.olderMessagesPaginationHandler
    }

    private var topPaginationIsOlder: Bool { type == .conversation }
    private var bottomPaginationIsOlder: Bool { type == .comments }

    private var topPaginationTargetID: String? {
        paginationTargetID(for: topPaginationHandler, fromTop: true)
    }

    private var bottomPaginationTargetID: String? {
        paginationTargetID(for: bottomPaginationHandler, fromTop: false)
    }

    private var lastReadIndicatorMessageID: String? {
        guard chatParams.showLastReadIndicator else { return nil }
        return sections
            .flatMap(\.rows)
            .dropFirst()
            .first { row in
                if case .readBy = row.message.status { return true }
                return false
            }?
            .id
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                paginationIndicator(for: topPaginationHandler, isOlder: topPaginationIsOlder)

                ForEach(Array(displayedSections.enumerated()), id: \.element.date) { element in
                    let sectionIndex = element.offset
                    let section = element.element

                    if sectionIndex == 0, let mainHeaderBuilder {
                        mainHeaderBuilder()
                    }

                    if chatParams.showDateHeaders {
                        dateHeader(for: section)
                    }

                    ForEach(type == .conversation ? Array(section.rows.reversed()) : section.rows) { row in
                        messageRow(row)
                    }
                }

                paginationIndicator(for: bottomPaginationHandler, isOlder: bottomPaginationIsOlder)
            }
            .padding(chatParams.contentInsets)
            .frame(maxWidth: .infinity)
            .scrollTargetLayout()
        }
        .coordinateSpace(name: "ExyteChatMessageScroll")
        .scrollPosition($scrollPosition, anchor: .top)
        .defaultScrollAnchor(type == .conversation ? .bottom : .top)
        .scrollIndicators(.hidden)
        .scrollDisabled(!chatParams.isScrollEnabled)
        .scrollDismissesKeyboard(chatParams.keyboardDismissMode)
        .swipeActionsContainer()
        .background(.background)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(
                contentOffset: geometry.contentOffset.y,
                contentHeight: geometry.contentSize.height,
                viewportHeight: geometry.containerSize.height,
                visibleMinY: geometry.visibleRect.minY,
                visibleMaxY: geometry.visibleRect.maxY
            )
        } action: { _, metrics in
            scrollMetrics = metrics
            chatParams.onContentOffsetChange?(metrics.contentOffset)

            let atTop = metrics.distanceFromTop <= 1
            let atBottom = metrics.distanceFromBottom <= 1
            isScrolledToBottom = type == .conversation ? atBottom : atTop

            if let handler = topPaginationHandler,
               case let .pixels(threshold) = handler.triggerType,
               metrics.distanceFromTop <= threshold {
                loadMore(handler, isOlder: topPaginationIsOlder)
            }

            if let handler = bottomPaginationHandler,
               case let .pixels(threshold) = handler.triggerType,
               metrics.distanceFromBottom <= threshold {
                loadMore(handler, isOlder: bottomPaginationIsOlder)
            }

            applyOffsetAdjustmentIfPossible()
        }
        .onChange(of: pendingScrollTo) { _, target in
            guard let target else { return }
            performScroll(to: target)
            pendingScrollTo = nil
        }
        .onPreferenceChange(MessageFramesPreferenceKey.self) { frames in
            messageFrames = frames
            applyOffsetAdjustmentIfPossible()
        }
        .onAppear {
            chatParams.onTransactionReady?(transaction)
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: viewModel.messageMenuRow?.id) { _, newValue in
            newValue != nil
        }
    }

    @ViewBuilder
    private func dateHeader(for section: MessagesSection) -> some View {
        if let dateHeaderBuilder {
            dateHeaderBuilder(section.date)
        } else {
            Text(section.formattedDate)
                .font(.caption2)
                .padding(.top, 30)
                .padding(.bottom, 8)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func paginationIndicator(for handler: PaginationHandler?, isOlder: Bool) -> some View {
        let isLoading = isOlder ? paginationState.olderInProgress : paginationState.newerInProgress
        if isLoading, let handler {
            handler.loadingIndicatorBuilder()
        }
    }

    private func messageRow(_ row: MessageRow) -> some View {
        VStack(spacing: 0) {
            if row.id == lastReadIndicatorMessageID {
                LastReadIndicatorView()
            }

            rowContent(row)
                .background(MessageMenuPreferenceViewSetter(id: row.id))
                .background(.background)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: MessageFramesPreferenceKey.self,
                            value: [row.id: geometry.frame(in: .named("ExyteChatMessageScroll"))]
                        )
                    }
                }
        }
        .id(row.id)
        .onAppear { messageDidAppear(row) }
    }

    @ViewBuilder
    private func rowContent(_ row: MessageRow) -> some View {
        let leading = swipeActions(at: .leading, for: row.message)
        let trailing = swipeActions(at: .trailing, for: row.message)

        ChatMessageView(
            viewModel: viewModel,
            messageBuilder: messageBuilder,
            row: row,
            chatType: type,
            messageParams: messageParams,
            isDisplayingMessageMenu: false
        )
        .applyIf(chatParams.showMessageMenuOnLongPress) {
            $0.simultaneousGesture(TapGesture())
                .onLongPressGesture {
                    viewModel.messageMenuRow = row
                }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: leading?.performsFirstActionWithFullSwipe ?? false) {
            if let leading {
                swipeButtons(leading.actions, for: row.message)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: trailing?.performsFirstActionWithFullSwipe ?? false) {
            if let trailing {
                swipeButtons(trailing.actions, for: row.message)
            }
        }
    }

    @ViewBuilder
    private func swipeButtons(_ actions: [any SwipeActionable], for message: Message) -> some View {
        ForEach(Array(actions.enumerated()), id: \.offset) { element in
            let action = element.element
            if action.activeFor(message) {
                Button {
                    action.action(message, viewModel.messageMenuAction())
                } label: {
                    action.content
                }
                .tint(action.background)
            }
        }
    }

    private func swipeActions(at edge: HorizontalEdge, for message: Message) -> ListSwipeAction? {
        let configuration = edge == .leading
            ? chatParams.listSwipeActions.leading
            : chatParams.listSwipeActions.trailing
        guard let configuration, configuration.actions.contains(where: { $0.activeFor(message) }) else {
            return nil
        }
        return configuration
    }

    private func messageDidAppear(_ row: MessageRow) {
        chatParams.onMessageAppear?(row.message)

        if row.id == topPaginationTargetID, let handler = topPaginationHandler {
            loadMore(handler, isOlder: topPaginationIsOlder)
        }
        if row.id == bottomPaginationTargetID, let handler = bottomPaginationHandler {
            loadMore(handler, isOlder: bottomPaginationIsOlder)
        }
    }

    private func paginationTargetID(for handler: PaginationHandler?, fromTop: Bool) -> String? {
        guard let handler,
              case let .cellIndex(offset) = handler.triggerType,
              !displayedRows.isEmpty else { return nil }
        let index = fromTop
            ? min(max(offset, 0), displayedRows.count - 1)
            : max(0, displayedRows.count - 1 - max(offset, 0))
        return displayedRows[index].id
    }

    private func loadMore(_ handler: PaginationHandler, isOlder: Bool) {
        guard handler.hasMoreToLoad else { return }
        if isOlder {
            guard !paginationState.olderInProgress else { return }
            paginationState.olderInProgress = true
        } else {
            guard !paginationState.newerInProgress else { return }
            paginationState.newerInProgress = true
        }

        Task { @MainActor in
            await handler.handleClosure()
            if isOlder {
                paginationState.olderInProgress = false
            } else {
                paginationState.newerInProgress = false
            }
        }
    }

    private func performScroll(to params: ScrollToParams) {
        switch params.scrollTo {
        case let .messageID(messageID, targetPosition, offset):
            scrollPosition.scrollTo(id: messageID, anchor: targetPosition.unitPoint)
            if offset != 0 {
                offsetAdjustment = OffsetAdjustment(
                    messageID: messageID,
                    position: targetPosition,
                    offset: offset
                )
                Task { @MainActor in
                    await Task.yield()
                    applyOffsetAdjustmentIfPossible()
                }
            }
        case let .contentOffset(offset):
            scrollPosition.scrollTo(y: offset)
        case .newestMessage:
            scrollPosition.scrollTo(edge: type == .conversation ? .bottom : .top)
        case .oldestMessage:
            scrollPosition.scrollTo(edge: type == .conversation ? .top : .bottom)
        }
    }

    private func applyOffsetAdjustmentIfPossible() {
        guard let adjustment = offsetAdjustment,
              let frame = messageFrames[adjustment.messageID] else { return }

        let alignedY: CGFloat
        switch adjustment.position {
        case .top:
            alignedY = 0
        case .middle:
            alignedY = scrollMetrics.viewportHeight / 2
        case .bottom:
            alignedY = scrollMetrics.viewportHeight
        }

        scrollPosition.scrollTo(y: scrollMetrics.contentOffset + frame.minY - alignedY + adjustment.offset)
        offsetAdjustment = nil
    }
}

private extension ChatScrollPosition {
    var unitPoint: UnitPoint {
        switch self {
        case .top: .top
        case .middle: .center
        case .bottom: .bottom
        }
    }
}
