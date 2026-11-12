//
//  InputView+AttachmentPreviews.swift
//  Chat
//

import SwiftUI

extension InputView {

    @ViewBuilder
    var viewOnTop: some View {
        if style == .message, !viewModel.attachments.medias.isEmpty {
            mediaAttachmentsPreview
        }
        if style == .message, !viewModel.attachments.documents.isEmpty {
            documentAttachmentsPreview
        }
        if style == .message, let staticLocation = viewModel.attachments.staticLocation {
            staticLocationAttachmentPreview(staticLocation)
        }
        if style == .message, let liveLocation = viewModel.attachments.liveLocation {
            liveLocationAttachmentPreview(liveLocation)
        }
        if let message = viewModel.attachments.replyMessage {
            VStack(spacing: 8) {
                Rectangle()
                    .foregroundColor(Color.secondary.opacity(0.12))
                    .frame(height: 2)

                HStack {
                    Image(systemName: "arrow.uturn.left")
                    Capsule()
                        .foregroundStyle(.tint)
                        .frame(width: 2)
                    VStack(alignment: .leading) {
                        Text(localization.replyToText + " " + message.user.name)
                            .font(.caption2)
                            .foregroundColor(Color.secondary)
                        if !message.attributedText.characters.isEmpty {
                            Text(message.attributedText)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundColor(Color.primary)
                        }
                    }
                    .padding(.vertical, 2)

                    Spacer()

                    if let first = message.attachments.first {
                        AsyncImageView(attachment: first, size: CGSize(width: 30, height: 30))
                            .viewSize(30)
                            .cornerRadius(4)
                            .padding(.trailing, 16)
                    }

                    if let _ = message.recording {
                        Image(systemName: "mic.fill")
                            .renderingMode(.template)
                            .foregroundStyle(.tint)
                    }

                    Image(systemName: "xmark")
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.attachments.replyMessage = nil
                            }
                        }
                }
                .padding(.horizontal, 26)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    var mediaAttachmentsPreview: some View {
        horizontalAttachmentsPreviewScroll {
            ForEach(viewModel.attachments.medias) { media in
                MediaAttachmentThumbnail(media: media) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.attachments.medias.removeAll { $0.id == media.id }
                    }
                }
            }
        }
    }

    var documentAttachmentsPreview: some View {
        horizontalAttachmentsPreviewScroll {
            ForEach(viewModel.attachments.documents) { document in
                DocumentAttachmentThumbnail(document: document) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.attachments.documents.removeAll { $0.id == document.id }
                    }
                }
            }
        }
    }

    func horizontalAttachmentsPreviewScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                content()
            }
            .padding(.top, 8)
            .padding(.horizontal, 26)
        }
    }

    func staticLocationAttachmentPreview(_ staticLocation: StaticLocation) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
                .renderingMode(.template)
                .foregroundColor(Color.primary)

            Text(String(format: "%.4f, %.4f", staticLocation.latitude, staticLocation.longitude))
                .font(.caption)
                .foregroundColor(Color.primary)
                .lineLimit(1)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.attachments.staticLocation = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 8)
    }

    func liveLocationAttachmentPreview(_ liveLocation: LiveLocation) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
                .renderingMode(.template)
                .foregroundStyle(.tint)

            Text(localization.liveLocationText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .lineLimit(1)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.attachments.liveLocation = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 8)
    }
}

// MARK: - Thumbnail views

private struct RemovableAttachmentThumbnail<Content: View>: View {
    @Environment(\.chatSize) var chatSize

    var onRemove: () -> Void
    @ViewBuilder var content: () -> Content

    private var thumbnailSize: CGFloat {
        chatSize.width / 5
    }

    var body: some View {
        content()
            .viewSize(thumbnailSize)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
                .offset(x: 6, y: -6)
            }
    }
}

private struct MediaAttachmentThumbnail: View {

    var media: DraftMedia
    var onRemove: () -> Void

    var body: some View {
        RemovableAttachmentThumbnail(onRemove: onRemove) {
            ZStack {
                ChatAsyncImage(url: media.thumbnailURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.12))
                    }
                }
                
                if media.type == .video {
                    Image(systemName: "play.circle.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 20))
                }
            }
        }
    }
}

private struct DocumentAttachmentThumbnail: View {

    var document: DocumentItem
    var onRemove: () -> Void

    var body: some View {
        RemovableAttachmentThumbnail(onRemove: onRemove) {
            VStack(spacing: 4) {
                Image(systemName: "doc.fill")
                    .resizable()
                    .scaledToFit()
                    .viewSize(28)

                Text(document.fileName)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.primary)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.12))
        }
    }
}
