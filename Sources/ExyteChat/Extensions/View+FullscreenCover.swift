import SwiftUI

extension View {
    func adaptiveFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented, content: content)
        #else
        fullScreenCover(isPresented: isPresented, content: content)
        #endif
    }

    func transparentFullScreenCover<Item, Content>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View where Item: Equatable, Item: Identifiable, Content: View {
        #if os(macOS)
        sheet(item: item) { _ in
            content()
                .presentationBackground(.clear)
        }
        #else
        fullScreenCover(item: item) { _ in
            content()
                .presentationBackground(.clear)
        }
        #endif
    }
}
