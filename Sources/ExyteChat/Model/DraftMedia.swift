import Foundation

/// A locally available image or video selected in the chat composer.
///
/// `url` points to the original file and `thumbnailURL` points to an image suitable for previews.
/// Both files are stored in the app's temporary directory. Copy them to permanent storage or upload
/// them before the app needs to retain a draft across launches.
public struct DraftMedia: Identifiable, Hashable, Sendable {
    public let id: String
    public let url: URL
    public let thumbnailURL: URL
    public let type: AttachmentType

    public init(
        id: String = UUID().uuidString,
        url: URL,
        thumbnailURL: URL? = nil,
        type: AttachmentType
    ) {
        self.id = id
        self.url = url
        self.thumbnailURL = thumbnailURL ?? url
        self.type = type
    }
}
