//
//  Created by Alex.M on 22.06.2022.
//

import Foundation
import SwiftUI

struct FullscreenMediaPages: View {

    @State private var viewModel: FullscreenMediaPagesViewModel
    var showShareButton: Bool = true
    var onClose: () -> Void

    @State private var shareItem: ShareItem?
    @State private var isPreparingShare = false
    @State private var showMinis = true
    @State private var shareRequestID = 0
    @State private var attachmentToShare: Attachment?

    init(
        viewModel: FullscreenMediaPagesViewModel,
        showShareButton: Bool = true,
        onClose: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.showShareButton = showShareButton
        self.onClose = onClose
    }

    private var tintColor: Color {
        .primary
    }

    var body: some View {
        VStack(spacing: 0) {
            if showMinis {
                headerView
            }

            mediaPagerView

            if showMinis {
                minisView
            }
        }
        .background {
            Rectangle().fill(.background).ignoresSafeArea()
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .task(id: shareRequestID) {
            let requestID = shareRequestID
            guard let attachment = attachmentToShare else { return }
            defer {
                if requestID == shareRequestID {
                    isPreparingShare = false
                    attachmentToShare = nil
                }
            }
            let url = await AttachmentSharing.prepareForSharing(attachment)
            guard !Task.isCancelled, requestID == shareRequestID else { return }
            shareItem = url.map(ShareItem.init)
        }
    }

    var headerView: some View {
        ZStack {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.large)
                        .padding(5)
                }
                .tint(tintColor)
                .padding(.leading, 10)

                Spacer()

                HStack(spacing: 20) {
                    if showShareButton {
                        if isPreparingShare {
                            ProgressView()
                                .tint(tintColor)
                                .viewSize(24)
                                .padding(5)
                        } else {
                            controlIcon(Image(systemName: "square.and.arrow.up")) {
                                shareCurrentAttachment()
                            }
                        }
                    }
                }
                .foregroundColor(tintColor)
                .padding(.trailing, 10)
            }

            #if os(macOS)
            HStack(spacing: 10) {
                Button {
                    moveAttachment(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .keyboardShortcut(.leftArrow)
                .disabled(viewModel.index == 0)
                .accessibilityLabel("Previous attachment")

                Text("\(viewModel.index + 1)/\(viewModel.attachments.count)")
                    .foregroundColor(tintColor)

                Button {
                    moveAttachment(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .keyboardShortcut(.rightArrow)
                .disabled(viewModel.index >= viewModel.attachments.count - 1)
                .accessibilityLabel("Next attachment")
            }
            #else
            Text("\(viewModel.index + 1)/\(viewModel.attachments.count)")
                .foregroundColor(tintColor)
            #endif
        }
        .padding(.bottom, 8)
    }

    var mediaPagerView: some View {
        #if os(macOS)
        Group {
            if viewModel.attachments.indices.contains(viewModel.index) {
                AttachmentsPage(attachment: viewModel.attachments[viewModel.index])
            }
        }
        .environment(viewModel)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture {
            withAnimation {
                showMinis.toggle()
            }
        }
        #else
        TabView(selection: $viewModel.index) {
            ForEach(viewModel.attachments.enumerated().map({ $0 }), id: \.offset) { (index, attachment) in
                AttachmentsPage(attachment: attachment)
                    .tag(index)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(viewModel)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onTapGesture {
            withAnimation {
                showMinis.toggle()
            }
        }
        #endif
    }

    var minisView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 2) {
                    ForEach(viewModel.attachments
                        .filter { $0.fullUploadStatus == nil || $0.fullUploadStatus == .complete }
                        .enumerated().map({ $0 }), id: \.offset) { (index, attachment) in
                            AttachmentCell(attachment: attachment, size: CGSize(width: 100, height: 100)) { _,_ in
                                withAnimation {
                                    viewModel.index = index
                                }
                            }
                            .cornerRadius(4)
                            .clipped()
                            .id(index)
                            .overlay {
                                if viewModel.index == index {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(.tint, lineWidth: 2)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                }
                .padding([.top, .horizontal], 12)
            }
            .onAppear {
                proxy.scrollTo(viewModel.index)
            }
            .onChange(of: viewModel.index) { _, newValue in
                withAnimation {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private extension FullscreenMediaPages {
    func moveAttachment(by offset: Int) {
        let nextIndex = viewModel.index + offset
        guard viewModel.attachments.indices.contains(nextIndex) else { return }
        viewModel.index = nextIndex
    }

    func controlIcon(_ image: Image, onTap: @escaping () -> Void) -> some View {
        image
            .resizable()
            .scaledToFit()
            .viewSize(24)
            .padding(5)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
    }

    func shareCurrentAttachment() {
        guard !isPreparingShare else { return }
        guard viewModel.attachments.indices.contains(viewModel.index) else { return }
        attachmentToShare = viewModel.attachments[viewModel.index]
        isPreparingShare = true
        shareRequestID += 1
    }
}

private extension FullscreenMediaPages {
    func closeSize(from size: CGSize) -> CGSize {
        CGSize(width: 0, height: max(size.height, 0))
    }
}
