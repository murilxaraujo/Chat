//
//  Created by Alex.M on 16.06.2022.
//

import SwiftUI

struct AttachmentsGrid: View {
    let onTap: (_ attachment: Attachment, _ isCancel: Bool) -> Void
    let isCurrentUser: Bool
    let maxImages: Int = 4 // TODO: Make injectable

    private let single: (Attachment)?
    private let grid: [Attachment]
    private let onlyOne: Bool

    private let hidden: String?
    private let showMoreAttachmentId: String?

    init(attachments: [Attachment], isCurrentUser: Bool,
         onTap: @escaping (_ attachment: Attachment, _ isCancel: Bool) -> Void) {
        var toShow = attachments

        if toShow.count > maxImages {
            toShow = attachments.prefix(maxImages).map({ $0 })
            hidden = "+\(attachments.count - (maxImages - 1))"
            showMoreAttachmentId = attachments[safe: (maxImages - 1)]?.id
        } else {
            hidden = nil
            showMoreAttachmentId = nil
        }
        if toShow.count % 2 == 0 {
            single = nil
            grid = toShow
        } else {
            single = toShow.first
            grid = toShow.dropFirst().map { $0 }
        }
        self.onlyOne = attachments.count == 1
        self.onTap = onTap
        self.isCurrentUser = isCurrentUser
    }

    var columns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        VStack(spacing: 4) {
            if let attachment = single {
                AttachmentCell(attachment: attachment, size: CGSize(width: 204, height: grid.isEmpty ? 200 : 100), showCancel: isCurrentUser, onTap: onTap)
                    .clipped()
                    .cornerRadius(onlyOne ? 0 : 12)
            }
            if !grid.isEmpty {
                ForEach(pair(), id: \.id) { pair in
                    HStack(spacing: 4) {
                        AttachmentCell(attachment: pair.left, size: CGSize(width: 100, height: 100), showCancel: isCurrentUser, onTap: onTap)
                            .clipped()
                            .cornerRadius(12)
                        AttachmentCell(attachment: pair.right, size: CGSize(width: 100, height: 100), showCancel: isCurrentUser, onTap: onTap)
                            .clipped()
                            .overlay {
                                if pair.right.id == showMoreAttachmentId, let hidden = hidden {
                                    ZStack {
                                        RadialGradient(
                                            colors: [
                                                .black.opacity(0.8),
                                                .black.opacity(0.6),
                                            ],
                                            center: .center,
                                            startRadius: 0,
                                            endRadius: 90
                                        )
                                        Text(hidden)
                                            .font(.body)
                                            .bold()
                                            .foregroundColor(.white)
                                    }
                                    .allowsHitTesting(false)
                                }
                            }
                            .cornerRadius(12)
                    }
                }
            }
        }
    }
}

private extension AttachmentsGrid {
    func pair() -> Array<AttachmentsPair> {
        return stride(from: 0, to: grid.count - 1, by: 2)
            .map { AttachmentsPair(left: grid[$0], right: grid[$0+1]) }
    }
}

struct AttachmentsPair {
    let left: Attachment
    let right: Attachment

    var id: String {
        left.id + "+" + right.id
    }
}

#if DEBUG
struct AttachmentsGrid_Preview: PreviewProvider {
    private static let examples: [[Attachment]] = [
        [Attachment(id: "one", url: URL(fileURLWithPath: "/Project brief.pdf"), type: .document, fileName: "Project brief.pdf")],
        [
            Attachment(id: "two-a", url: URL(fileURLWithPath: "/Meeting notes.pdf"), type: .document, fileName: "Meeting notes.pdf"),
            Attachment(id: "two-b", url: URL(fileURLWithPath: "/Wireframes.sketch"), type: .document, fileName: "Wireframes.sketch")
        ],
        [
            Attachment(id: "many-a", url: URL(fileURLWithPath: "/Roadmap.pdf"), type: .document, fileName: "Roadmap.pdf"),
            Attachment(id: "many-b", url: URL(fileURLWithPath: "/Research.pdf"), type: .document, fileName: "Research.pdf"),
            Attachment(id: "many-c", url: URL(fileURLWithPath: "/Prototype.fig"), type: .document, fileName: "Prototype.fig"),
            Attachment(id: "many-d", url: URL(fileURLWithPath: "/Sprint plan.pdf"), type: .document, fileName: "Sprint plan.pdf"),
            Attachment(id: "many-e", url: URL(fileURLWithPath: "/Budget.xlsx"), type: .document, fileName: "Budget.xlsx")
        ]
    ]

    static var previews: some View {
        Group {
            ForEach(examples.indices, id: \.self) { index in
                ScrollView {
                    AttachmentsGrid(attachments: examples[index], isCurrentUser: true, onTap: { _, _ in })
                        .padding()
                        .background(Color.white)
                }
            }
            .padding()
            .background(Color.secondary)
        }
    }
}
#endif
