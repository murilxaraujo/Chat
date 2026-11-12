import SwiftUI

public struct ZoomableContainer<Content: View>: View {
    let content: Content
    let maxScale: CGFloat
    let doubleTapScale: CGFloat

    @State private var currentScale: CGFloat = 1
    @State private var contentOffset = CGSize.zero
    @GestureState private var magnification: CGFloat = 1
    @GestureState private var dragOffset = CGSize.zero

    public init(
        maxScale: CGFloat = 4,
        doubleTapScale: CGFloat = 4,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.maxScale = max(1, maxScale)
        self.doubleTapScale = min(max(1, doubleTapScale), max(1, maxScale))
    }

    public var body: some View {
        GeometryReader { geometry in
            content
                .scaleEffect(currentScale * magnification)
                .offset(
                    x: contentOffset.width + dragOffset.width,
                    y: contentOffset.height + dragOffset.height
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(magnifyGesture)
                .simultaneousGesture(dragGesture)
                .onTapGesture(count: 2) { location in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if currentScale > 1 {
                            currentScale = 1
                            contentOffset = .zero
                        } else {
                            currentScale = doubleTapScale
                            let scaleDelta = doubleTapScale - 1
                            contentOffset = CGSize(
                                width: (geometry.size.width / 2 - location.x) * scaleDelta,
                                height: (geometry.size.height / 2 - location.y) * scaleDelta
                            )
                        }
                    }
                }
                .clipped()
        }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($magnification) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                currentScale = min(maxScale, max(1, currentScale * value.magnification))
                if currentScale == 1 {
                    contentOffset = .zero
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($dragOffset) { value, state, _ in
                guard currentScale > 1 else { return }
                state = value.translation
            }
            .onEnded { value in
                guard currentScale > 1 else { return }
                contentOffset.width += value.translation.width
                contentOffset.height += value.translation.height
            }
    }
}
