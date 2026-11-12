import Foundation

enum DocumentImporter {
    static func importItems(from urls: [URL]) -> [DocumentItem] {
        urls.compactMap { sourceURL in
            let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            guard let localURL = try? NativeMediaImporter.copyToTemporaryDirectory(from: sourceURL) else {
                return nil
            }

            let fileSize = try? FileManager.default
                .attributesOfItem(atPath: localURL.path)[.size] as? Int
            return DocumentItem(
                url: localURL,
                fileName: sourceURL.lastPathComponent,
                fileSize: fileSize ?? nil
            )
        }
    }
}
