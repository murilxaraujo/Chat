import AVFoundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum NativeMediaImporter {

    static func importItems(_ items: [PhotosPickerItem]) async -> [DraftMedia] {
        var importedMedia: [DraftMedia] = []

        for item in items {
            guard !Task.isCancelled,
                  let type = mediaType(for: item),
                  let file = try? await item.loadTransferable(type: ImportedMediaFile.self),
                  let media = await makeDraftMedia(url: file.url, type: type) else {
                continue
            }
            importedMedia.append(media)
        }

        return importedMedia
    }

    static func makeDraftMedia(url: URL, type: AttachmentType) async -> DraftMedia? {
        guard type == .image || type == .video else { return nil }

        guard type == .video else {
            return DraftMedia(url: url, type: .image)
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        guard let cgImage = try? await generator.image(at: .zero).image,
              let data = jpegData(from: cgImage, compressionQuality: 0.82),
              let thumbnailURL = try? writeTemporaryFile(data, fileExtension: "jpg") else {
            return nil
        }

        return DraftMedia(url: url, thumbnailURL: thumbnailURL, type: .video)
    }

    private static func jpegData(from image: CGImage, compressionQuality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func copyToTemporaryDirectory(from sourceURL: URL) throws -> URL {
        let destinationURL = makeTemporaryFileURL(fileExtension: sourceURL.pathExtension)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    static func writeTemporaryFile(_ data: Data, fileExtension: String) throws -> URL {
        let destinationURL = makeTemporaryFileURL(fileExtension: fileExtension)
        try data.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    static func makeTemporaryFileURL(fileExtension: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExyteChatMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var url = directory.appendingPathComponent(UUID().uuidString)
        if !fileExtension.isEmpty {
            url.appendPathExtension(fileExtension)
        }
        return url
    }

    static func imageFileExtension(for data: Data) -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              let fileExtension = UTType(type)?.preferredFilenameExtension else {
            return "jpg"
        }
        return fileExtension
    }

    private static func mediaType(for item: PhotosPickerItem) -> AttachmentType? {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            return .video
        }
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .image) }) {
            return .image
        }
        return nil
    }

}

struct ImportedMediaFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .item) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            let copyURL = try NativeMediaImporter.copyToTemporaryDirectory(from: received.file)
            return Self(url: copyURL)
        }
    }
}
