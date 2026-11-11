import SwiftUI
import UIKit

/// Uses Apple's `AsyncImage` for network URLs and loads local file URLs directly.
/// The `asset://name` form is used by the example app for images in its asset catalog.
struct ChatAsyncImage<Content: View>: View {

    @State private var localPhase: AsyncImagePhase = .empty

    private let url: URL?
    private let scale: CGFloat
    private let transaction: Transaction
    private let content: (AsyncImagePhase) -> Content

    init(
        url: URL?,
        scale: CGFloat = 1,
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.scale = scale
        self.transaction = transaction
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if url?.scheme == "asset", let name = url?.host {
            if let image = UIImage(named: name) {
                content(.success(Image(uiImage: image)))
            } else {
                content(.empty)
            }
        } else if let url, url.isFileURL {
            content(localPhase)
                .task(id: url) {
                    await loadLocalImage(from: url)
                }
        } else {
            AsyncImage(url: url, scale: scale, transaction: transaction, content: content)
        }
    }

    private func loadLocalImage(from url: URL) async {
        localPhase = .empty

        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: url)
            }.value

            guard !Task.isCancelled else { return }
            guard let image = UIImage(data: data, scale: scale) else {
                throw LocalImageError.invalidData
            }

            withAnimation(transaction.animation) {
                localPhase = .success(Image(uiImage: image))
            }
        } catch {
            guard !Task.isCancelled else { return }
            withAnimation(transaction.animation) {
                localPhase = .failure(error)
            }
        }
    }

    private enum LocalImageError: Error {
        case invalidData
    }
}
