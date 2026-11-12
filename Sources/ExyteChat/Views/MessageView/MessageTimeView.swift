//
//  Created by Alex.M on 08.07.2022.
//

import SwiftUI

struct MessageTimeView: View {

    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
    }
}

struct MessageTimeWithCapsuleView: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.primary)
            .opacity(0.8)
            .padding(.top, 4)
            .padding(.bottom, 4)
            .padding(.horizontal, 8)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
            }
    }
}

#Preview("Message timestamps") {
    VStack(alignment: .leading, spacing: 12) {
        MessageTimeView(text: "9:41 AM")
        MessageTimeWithCapsuleView(text: "9:41 AM")
    }
    .padding()
    .background(.background)
}
