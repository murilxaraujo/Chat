//
//  ChatInputBar.swift
//  Chat
//

import SwiftUI

/// A native SwiftUI layout for a chat or agent input bar.
///
/// The bar provides a Liquid Glass editing area, with leading and primary-action
/// controls floating outside it. Each region is a content-builder slot, so callers
/// can use standard SwiftUI controls or provide a completely custom view.
///
/// ```swift
/// ChatInputBar(
///     leading: {
///         Button("Attach", systemImage: "plus") { attach() }
///             .labelStyle(.iconOnly)
///             .buttonStyle(.glassProminent)
///             .buttonBorderShape(.circle)
///             .controlSize(.large)
///     },
///     content: { TextField("Message", text: $text, axis: .vertical) },
///     action: {
///         Button("Send", systemImage: "paperplane.fill", action: send)
///             .buttonStyle(.borderedProminent)
///             .buttonBorderShape(.circle)
///     }
/// )
/// ```
///
/// The action builder also accepts a fully custom button label:
///
/// ```swift
/// Button(action: send) {
///     HStack {
///         Text("Send to agent")
///         Image(systemName: "arrow.up")
///     }
/// }
/// ```
public struct ChatInputBar<Accessory: View, Leading: View, Content: View, Trailing: View, Action: View>: View {
    private let accessory: Accessory
    private let leading: Leading
    private let content: Content
    private let trailing: Trailing
    private let action: Action

    private let controlHeight: CGFloat
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat
    private let actionSpacing: CGFloat
    private let cornerRadius: CGFloat

    /// Creates a composer from independent accessory, leading, editor, trailing,
    /// and primary-action regions.
    ///
    /// Use the region builders to compose native SwiftUI controls. To replace the
    /// entire composer in `ChatView`, use its `inputViewBuilder` instead.
    public init(
        controlHeight: CGFloat = 48,
        horizontalPadding: CGFloat = 12,
        verticalPadding: CGFloat = 8,
        actionSpacing: CGFloat = 20,
        cornerRadius: CGFloat = 18,
        @ContentBuilder accessory: () -> Accessory = { EmptyView() },
        @ContentBuilder leading: () -> Leading = { EmptyView() },
        @ContentBuilder content: () -> Content,
        @ContentBuilder trailing: () -> Trailing = { EmptyView() },
        @ContentBuilder action: () -> Action
    ) {
        self.controlHeight = controlHeight
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.actionSpacing = actionSpacing
        self.cornerRadius = cornerRadius
        self.accessory = accessory()
        self.leading = leading()
        self.content = content()
        self.trailing = trailing()
        self.action = action()
    }

    public var body: some View {
        VStack(spacing: 8) {
            accessory

            HStack(alignment: .bottom, spacing: actionSpacing) {
                leading
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)

                HStack(alignment: .bottom, spacing: 0) {
                    content
                        .frame(minHeight: controlHeight)
                    trailing
                        .frame(minHeight: controlHeight)
                }
                .padding(.horizontal, horizontalPadding)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
                .frame(maxWidth: .infinity)

                action
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
    }
}

#Preview("Composable input bar") {
    ChatInputBar(
        leading: {
            Button("Attach", systemImage: "plus") {}
                .labelStyle(.iconOnly)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        },
        content: {
            TextField("Ask anything…", text: .constant(""), axis: .vertical)
                .padding(.vertical, 10)
        },
        action: {
            Button("Send", systemImage: "paperplane.fill") {}
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        }
    )
    .padding(8)
}
