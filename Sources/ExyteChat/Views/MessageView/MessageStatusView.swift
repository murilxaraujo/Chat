//
//  Created by Alex.M on 07.07.2022.
//

import SwiftUI

struct MessageStatusView: View {


    let status: Message.Status
    let onRetry: () -> Void

    var body: some View {
        Group {
            switch status {
            case .sending:
                statusImageStyled(image: Image(systemName: "clock"), style: Color.secondary)
            case .sent:
                statusImageStyled(image: Image(systemName: "checkmark"), style: Color.secondary)
            case .delivered:
                statusImageStyled(image: Image(systemName: "checkmark"), style: Color.secondary)
            case .readBy:
                statusImageStyled(image: Image(systemName: "checkmark"), style: AnyShapeStyle(.tint))
            case .error:
                Button(action: onRetry) {
                    statusImageStyled(image: Image(systemName: "exclamationmark.circle.fill"), style: Color.red)
                }
            }
        }
    }

    private func statusImageStyled<S: ShapeStyle>(image: Image, style: S) -> some View {
        image
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(style)
            .frame(width: 40)
    }
}

struct SwiftUIView_Previews: PreviewProvider {
    
    static var previews: some View {
        VStack {
            MessageStatusView(status: .sending, onRetry: {})
            MessageStatusView(status: .sent, onRetry: {})
            MessageStatusView(status: .delivered, onRetry: {})
            MessageStatusView(status: .readBy([]), onRetry: {})
            MessageStatusView(status: .error(emptyDraft()), onRetry: {})
        }
    }

    private static func emptyDraft() -> DraftMessage {
        return DraftMessage(
            id: nil,
            text: "",
            medias: [],
            recording: nil,
            replyMessage: nil,
            createdAt: Date()
        )

    }
}
