//
//  Created by Alex.M on 16.06.2022.
//

import SwiftUI

public struct AttachmentCell: View {


    let attachment: Attachment
    let size: CGSize
    let showCancel: Bool
    let onTap: (_ attachment: Attachment, _ isCancel: Bool) -> Void

    public init(
        attachment: Attachment, size: CGSize, showCancel: Bool = false,
        onTap: @escaping (_ attachment: Attachment, _ isCancel: Bool) -> Void
    ) {
        self.attachment = attachment
        self.size = size
        self.showCancel = showCancel
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if attachment.type == .image {
                ZStack {
                    content
                    if let status = attachment.fullUploadStatus {
                        switch status {
                        case .inProgress(.none):         // uploading status handled but not percent, simply show progress view
                            uploadingOverlay(percent: nil)
                        case .inProgress(let percent?):  // full upload status handling with percent, shows progress view with percent
                            uploadingOverlay(percent: percent)
                        case .complete:
                            EmptyView()
                        case .cancelled:
                            cancelledOverlay
                        case .error:
                            errorOverlay
                        }
                    } else {  // upload status not handled assumes that content is uploaded before being sent to receiver
                        EmptyView()
                    }
                }
            } else if attachment.type == .video {
                ZStack {
                    content
                    if let status = attachment.fullUploadStatus {
                        switch status {
                        case .inProgress(.none):
                            uploadingOverlay(percent: nil)
                        case .inProgress(let percent?):
                            uploadingOverlay(percent: percent)
                        case .complete:
                            VStack {
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                        case .cancelled:
                            cancelledOverlay
                        case .error:
                            errorOverlay
                        }
                    } else {
                        VStack {
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.white)
                            Spacer()
                        }
                    }
                }
            } else if attachment.type == .document {
                documentContent
            } else {
                content
                    .overlay {
                        Text("Unknown", bundle: .module)
                    }
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .simultaneousGesture(attachmentTapGesture)
    }

    private var documentContent: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.fill")
                .font(.system(size: 32))
                .foregroundStyle(.tint)

            Text(attachment.fileName ?? attachment.full.lastPathComponent)
                .font(.caption2)
                .foregroundColor(Color.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.12))
    }

    @ViewBuilder
    private func uploadingOverlay(percent: Int?) -> some View {
        Color.white.opacity(0.8)
        if showCancel {
            Image(systemName: "xmark.circle.fill")
                .resizable()
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.4))
                .viewSize(36)
        }
        VStack {
            HStack {
                Spacer()
                if let percent {
                    AttachmentUploadStatusCapsuleView(percent)
                        .padding(4)
                } else {
                    AttachmentUploadStatusCapsuleView()
                        .padding(4)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var cancelledOverlay: some View {
        Color.white.opacity(0.8)
        VStack {
            HStack {
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .resizable()
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.4))
                    .viewSize(26)
                    .padding(4)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var errorOverlay: some View {
        Color.white.opacity(0.8)
        VStack {
            HStack {
                Spacer()
                Image(systemName: "exclamationmark.circle.fill")
                    .resizable()
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.4))
                    .viewSize(26)
                    .padding(4)
            }
            Spacer()
        }
    }

    private var attachmentTapGesture: AnyGesture<Void>? {
        if let status = attachment.fullUploadStatus {
            switch status {
            case .cancelled: return nil
            case .error: return nil
            case .inProgress(_):
                if showCancel {
                    return AnyGesture(TapGesture().onEnded { onTap(attachment, true) })
                }
                else {
                    // only the sender can cancel an upload attachment
                    return nil
                }
            case .complete: return AnyGesture(TapGesture().onEnded { onTap(attachment, false) })
            }
        }

        // attachments are uploaded before displayed so show play button
        return AnyGesture(TapGesture().onEnded { onTap(attachment, false) })

    }

    var content: some View {
        AsyncImageView(attachment: attachment, size: size)
    }
}

struct AsyncImageView: View {


    let attachment: Attachment
    let size: CGSize

    var body: some View {
        ChatAsyncImage(url: attachment.thumbnail) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .foregroundColor(Color.secondary.opacity(0.08))
                .frame(width: size.width, height: size.height)
            ActivityIndicator(size: 30, showBackground: false)
        }
    }
}

#Preview("Document attachment") {
    AttachmentCell(
        attachment: Attachment(
            id: "preview-document",
            url: URL(fileURLWithPath: "/Project brief.pdf"),
            type: .document,
            fileName: "Project brief.pdf"
        ),
        size: CGSize(width: 120, height: 112),
        onTap: { _, _ in }
    )
    .padding()
}
