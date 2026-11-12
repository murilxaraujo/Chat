//
//  Created by Alex.M on 14.06.2022.
//

import SwiftUI

struct TextInputView: View {
    
    
    @Environment(GlobalFocusState.self) private var globalFocusState
    
    @Binding var text: String
    var inputFieldId: UUID
    var style: InputViewStyle
    var availableInputs: [AvailableInputType]
    var localization: ChatLocalization
    
    var body: some View {
        @Bindable var focusState = globalFocusState
        TextField("", text: $text, prompt: Text(style == .message ? localization.inputPlaceholder : localization.signatureText)
            .foregroundColor(style == .message ? Color.secondary : Color.secondary), axis: .vertical)
            .customFocus($focusState.focus, equals: .uuid(inputFieldId))
            .foregroundColor(style == .message ? Color.primary : Color.primary)
            .padding(.vertical, 10)
            .padding(.leading, !isAttachmentsAvailable() ? 12 : 0)
            .simultaneousGesture(
                TapGesture().onEnded {
                    focusState.focus = .uuid(inputFieldId)
                }
            )
    }
    
    private func isAttachmentsAvailable() -> Bool {
        let attachmentTypes: [AvailableInputType] = [.media, .document, .staticLocation, .liveLocation]
        return attachmentTypes.contains { availableInputs.contains($0) }
    }
}
