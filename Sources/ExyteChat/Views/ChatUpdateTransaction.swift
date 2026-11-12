import SwiftUI

/// Applies a message-store update with a SwiftUI transaction.
@MainActor
public final class ChatUpdateTransaction {
    public enum AnimationMode: Sendable {
        case none
        case keepStable
        case natural
    }

    public func callAsFunction(animated: Bool, _ updates: @MainActor () -> Void) async {
        await callAsFunction(animationMode: animated ? .natural : .none, updates)
    }

    public func callAsFunction(
        animationMode: AnimationMode = .natural,
        _ updates: @MainActor () -> Void
    ) async {
        switch animationMode {
        case .natural:
            withAnimation(.default, updates)
        case .none, .keepStable:
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, updates)
        }
    }
}
