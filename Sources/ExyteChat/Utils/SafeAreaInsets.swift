import SwiftUI

private struct ChatSafeAreaInsetsKey: EnvironmentKey {
    static let defaultValue = EdgeInsets()
}

extension EnvironmentValues {
    var chatSafeAreaInsets: EdgeInsets {
        get { self[ChatSafeAreaInsetsKey.self] }
        set { self[ChatSafeAreaInsetsKey.self] = newValue }
    }
}
