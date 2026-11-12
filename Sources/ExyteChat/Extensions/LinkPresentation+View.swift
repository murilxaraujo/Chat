import LinkPresentation
import SwiftUI

/// A SwiftUI link card that uses LinkPresentation for metadata, without embedding LPLinkView.
struct LinkPreviewView: View {
    @State private var metadata: LinkPreviewMetadata
    private static let cache = LinkMetadataCache()

    init(url: URL) {
        if let cached = Self.cache.get(forURL: url) {
            metadata = .enriched(with: cached)
        } else {
            metadata = .placeholder(for: url)
        }
    }

    private var url: URL? {
        switch metadata {
        case .placeholder(let url): url
        case .enriched(let metadata): metadata.url ?? metadata.originalURL
        }
    }

    private var title: String {
        switch metadata {
        case .placeholder(let url): url.host ?? url.absoluteString
        case .enriched(let metadata): metadata.title ?? metadata.url?.host ?? metadata.originalURL?.host ?? "Link"
        }
    }

    private var subtitle: String? {
        url?.host
    }

    private func fetchMetadata(for url: URL) async {
        guard case .placeholder = metadata else { return }
        let provider = LPMetadataProvider()
        guard let fetched = try? await provider.startFetchingMetadata(for: url) else { return }
        metadata = .enriched(with: fetched)
        Self.cache.insert(fetched, forURL: url)
    }

    var body: some View {
        Group {
            if let url {
                Link(destination: url) {
                    card
                }
                .buttonStyle(.plain)
            } else {
                card
            }
        }
        .task(id: url) {
            if case .placeholder(let url) = metadata {
                await fetchMetadata(for: url)
            }
        }
        .animation(.default, value: title)
    }

    private var card: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(Color.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(Color.secondary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

#Preview {
    LinkPreviewView(url: URL(string: "https://example.org")!)
}
