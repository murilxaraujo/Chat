//
//  ActivityIndicator.swift
//
//
//  Created by Alisa Mylnikova on 01.09.2023.
//

import SwiftUI

struct ActivityIndicator: View {

    var size: CGFloat = 50
    var showBackground = true
    var color: Color? = nil

    var body: some View {
        ZStack {
            if showBackground {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
                    .opacity(0.8)
                    .viewSize(100)
            }

            ProgressView()
            .tint(color)
                .frame(width: size, height: size)
        }
    }
}

#Preview("Activity indicators") {
    HStack(spacing: 24) {
        ActivityIndicator()
        ActivityIndicator(size: 28, showBackground: false)
    }
    .padding()
}
