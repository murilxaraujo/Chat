import Foundation
import SwiftUI

struct ShareSheet: View {
    @Environment(\.dismiss) private var dismiss

    let activityItems: [URL]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "square.and.arrow.up")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)

                Text(activityItems.count == 1 ? "Ready to share" : "Ready to share \(activityItems.count) files")
                    .font(.headline)

                ShareLink(items: activityItems, subject: Text("Attachments")) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

enum AttachmentSharing {
    /// Resolves a local, shareable file URL for an attachment, downloading it first if it's remote.
    static func prepareForSharing(_ attachment: Attachment) async -> URL? {
        if attachment.full.isFileURL {
            return attachment.full
        }

        do {
            let (tempURL, response) = try await URLSession.shared.download(from: attachment.full)
            let fileExtension = response.suggestedFilename.flatMap { ($0 as NSString).pathExtension.nonEmpty }
                ?? attachment.full.pathExtension.nonEmpty
                ?? (attachment.type == .video ? "mp4" : "jpg")
            let destinationURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            return destinationURL
        } catch {
            print("[AttachmentSharing] Failed to download attachment for sharing: \(error)")
            return nil
        }
    }

    /// Resolves local, shareable file URLs for multiple attachments concurrently.
    static func prepareForSharing(_ attachments: [Attachment]) async -> [URL] {
        await withTaskGroup(of: (Int, URL?).self) { group in
            for (index, attachment) in attachments.enumerated() {
                group.addTask {
                    (index, await prepareForSharing(attachment))
                }
            }

            var urlsByIndex = [Int: URL]()
            for await (index, url) in group {
                urlsByIndex[index] = url
            }
            return urlsByIndex.keys.sorted().compactMap { urlsByIndex[$0] }
        }
    }
}
