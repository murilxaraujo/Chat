import SwiftUI

@MainActor
public final class KeyboardState: ObservableObject {
    @Published private(set) public var isShown = false

    private var dismissFocusedInput: () -> Void = {}

    func configure(isShown: Bool, dismiss: @escaping () -> Void) {
        self.isShown = isShown
        dismissFocusedInput = dismiss
    }

    func update(isShown: Bool) {
        self.isShown = isShown
    }

    /// Dismisses the currently focused SwiftUI text input.
    public func dismissKeyboard() {
        dismissFocusedInput()
    }
}
