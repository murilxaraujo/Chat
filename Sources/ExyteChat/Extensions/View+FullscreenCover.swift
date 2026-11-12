import SwiftUI

extension View {
    func transparentFullScreenCover<Item, Content>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View where Item: Equatable, Item: Identifiable, Content: View {
        fullScreenCover(item: item) { _ in
            content()
                .presentationBackground(.clear)
        }
    }
}
