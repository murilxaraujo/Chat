import SwiftUI
import ImageIO

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
            // SwiftUI's named-image initializer doesn't provide a failable asset lookup.
            content(.success(Image(name, bundle: .main)))
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
            guard let image = image(from: data) else {
                throw LocalImageError.invalidData
            }

            withAnimation(transaction.animation) {
                localPhase = .success(image)
            }
        } catch {
            guard !Task.isCancelled else { return }
            withAnimation(transaction.animation) {
                localPhase = .failure(error)
            }
        }
    }

    private func image(from data: Data) -> Image? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = Image.Orientation(cgImagePropertyOrientation: rawOrientation)

        return Image(
            cgImage,
            scale: scale,
            orientation: orientation,
            label: Text(verbatim: "")
        )
    }

    private enum LocalImageError: Error {
        case invalidData
    }
}

private extension Image.Orientation {
    init(cgImagePropertyOrientation: UInt32) {
        switch cgImagePropertyOrientation {
        case 2: self = .upMirrored
        case 3: self = .down
        case 4: self = .downMirrored
        case 5: self = .leftMirrored
        case 6: self = .right
        case 7: self = .rightMirrored
        case 8: self = .left
        default: self = .up
        }
    }
}
