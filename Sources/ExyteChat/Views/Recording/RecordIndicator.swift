//
//  RecordIndicator.swift
//  
//
//  Created by Alisa Mylnikova on 10.03.2023.
//

import SwiftUI

struct RecordIndicator: View {

    let count = 2

    var body: some View {
        let animation = Animation
            .linear(duration: 1)
            .repeatForever(autoreverses: false)

        ForEach(0..<count, id: \.self) { index in
            GrowingCircleIndicatorView(animation: animation.delay(CGFloat(index) * 0.5))
        }
    }
}

struct GrowingCircleIndicatorView: View {

    let animation: Animation

    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 1

    var body: some View {

        return Circle()
            .scaleEffect(scale)
            .opacity(opacity)
            .task {
                do {
                    try await Task.sleep(for: .milliseconds(10))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                withAnimation(animation) {
                    scale = 1
                    opacity = 0
                }
            }
    }
}

#Preview("Recording indicator") {
    ZStack {
        RecordIndicator()
            .foregroundStyle(.red)
        Circle()
            .fill(.red)
            .frame(width: 12, height: 12)
    }
    .frame(width: 48, height: 48)
}
