//
//  Created by Alex.M on 20.06.2022.
//

import SwiftUI

struct AttachmentsPage: View {
    @Environment(\.openURL) private var openURL

    @EnvironmentObject var mediaPagesViewModel: FullscreenMediaPagesViewModel

    let attachment: Attachment

    var body: some View {
        if attachment.type == .image {
            ZoomableContainer {
                ChatAsyncImage(url: attachment.full) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    default:
                        ActivityIndicator()
                    }
                }
            }
        } else if attachment.type == .video {
            VideoView(viewModel: VideoViewModel(attachment: attachment))
        } else if attachment.type == .document {
            documentView
        } else {
            Rectangle()
                .foregroundStyle(.secondary.opacity(0.15))
                .frame(minWidth: 100, minHeight: 100)
                .frame(maxHeight: 200)
                .overlay {
                    Text("Unknown", bundle: .module)
                }
        }
    }

    private var documentView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text(attachment.fileName ?? attachment.full.lastPathComponent)
                .foregroundColor(Color.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                openURL(attachment.full)
            } label: {
                Text("Open", bundle: .module)
                    .padding(20, 10)
                    .background(Capsule().fill(Color.primary.opacity(0.15)))
                    .foregroundColor(Color.primary)
            }
        }
    }
}
