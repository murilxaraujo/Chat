//
//  Created by Alex.M on 20.06.2022.
//

import Foundation
import SwiftUI

struct FrameGetter: ViewModifier {

    @Binding var frame: CGRect

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global).integral
        } action: { newFrame in
            guard frame != newFrame else { return }
            frame = newFrame
        }
    }
}

struct SizeGetter: ViewModifier {
    @Binding var size: CGSize

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            guard size != newSize else { return }
            size = newSize
        }
    }
}

struct MaxHeightGetter: ViewModifier {
    @Binding var height: CGFloat

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            guard newHeight > height else { return }
            height = newHeight
        }
    }
}

extension View {

    func frameGetter(_ frame: Binding<CGRect>) -> some View {
        modifier(FrameGetter(frame: frame))
    }

    func sizeGetter(_ size: Binding<CGSize>) -> some View {
        modifier(SizeGetter(size: size))
    }
    
    func maxHeightGetter(_ height: Binding<CGFloat>) -> some View {
        modifier(MaxHeightGetter(height: height))
    }
}

struct FinalMeasuringTrickView<Content: View>: View {
    @Binding var size: CGSize
    @State private var rawSize: CGSize = .zero

    let content: () -> Content

    var body: some View {
        content()
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            if geo.size.height != 0 {
                                rawSize = geo.size
                            }
                        }
                        .onChange(of: geo.size) { _ , newSize in
                            if newSize.height != 0 {
                                rawSize = newSize
                            }
                        }
                }
            )
            .task(id: rawSize) {
                let measuredSize = rawSize
                guard measuredSize.height != 0 else { return }
                do {
                    try await Task.sleep(for: .milliseconds(16)) // 1 frame
                } catch {
                    return
                }
                guard !Task.isCancelled, rawSize == measuredSize else { return }
                size = measuredSize
            }
            .hidden()
    }
}
