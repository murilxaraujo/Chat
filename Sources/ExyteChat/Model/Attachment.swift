//
//  Created by Alex.M on 16.06.2022.
//

import Foundation

public enum AttachmentType: String, Codable, Hashable, Sendable {
    case image
    case video
    case document

    public var title: String {
        switch self {
        case .image:
            return "Image"
        case .document:
            return "Document"
        default:
            return "Video"
        }
    }

}

public struct Attachment: Codable, Identifiable, Hashable, Sendable {
    
    public enum UploadStatus: Sendable, Codable, Hashable {
        case inProgress(Int?) // value = percent upto 99%, nil no percent shown, progress indicator only
        case complete
        case cancelled
        case error
        
        public static func == (lhs: UploadStatus, rhs: UploadStatus) -> Bool {
            switch (lhs, rhs) {
            case (.error, .error):
                return true
            case (.complete, .complete):
                return true
            case (.cancelled, .cancelled):
                return true
            case (.inProgress(let lhsPercent), .inProgress(let rhsPercent)):
                return lhsPercent == rhsPercent
            default:
                return false
            }
        }
    }
    
    
    public let id: String
    public let thumbnail: URL
    public let full: URL
    public let fullUploadStatus: UploadStatus?
    public let type: AttachmentType
    /// Used for .document attachments
    public let fileName: String?
    public let fileSize: Int?

    public init(
        id: String,
        thumbnail: URL,
        full: URL,
        type: AttachmentType,
        fullUploadStatus: UploadStatus? = nil,
        fileName: String? = nil,
        fileSize: Int? = nil
    ) {
        self.id = id
        self.thumbnail = thumbnail
        self.full = full
        self.type = type
        self.fullUploadStatus = fullUploadStatus
        self.fileName = fileName
        self.fileSize = fileSize
    }

    public init(
        id: String,
        url: URL,
        type: AttachmentType,
        fileName: String? = nil,
        fileSize: Int? = nil
    ) {
        self.init(
            id: id,
            thumbnail: url,
            full: url,
            type: type,
            fileName: fileName,
            fileSize: fileSize
        )
    }

    public func copy(
        id: String? = nil,
        thumbnail: URL? = nil,
        full: URL? = nil,
        fullUploadStatus: UploadStatus? = nil,
        type: AttachmentType? = nil,
        fileName: String? = nil,
        fileSize: Int? = nil
    ) -> Attachment {
        Attachment(
            id: id ?? self.id,
            thumbnail: thumbnail ?? self.thumbnail,
            full: full ?? self.full,
            type: type ?? self.type,
            fullUploadStatus: fullUploadStatus ?? self.fullUploadStatus,
            fileName: fileName ?? self.fileName,
            fileSize: fileSize ?? self.fileSize
        )
    }
}
