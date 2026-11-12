import SwiftUI

/// A SwiftUI text field for entering reactions. The system keyboard provides emoji input
/// through its standard emoji key; apps can't select the emoji keyboard programmatically.
struct EmojiTextField: View {
    var placeholder = ""
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
#if os(iOS)
            .textInputAutocapitalization(.never)
#endif
    }
}
