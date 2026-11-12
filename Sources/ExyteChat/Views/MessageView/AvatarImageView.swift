//
//  Created by Alex.M on 07.07.2022.
//

import SwiftUI

struct AvatarImageView: View {

    let url: URL?
    let avatarSize: CGFloat

    var body: some View {
        ChatAsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color.gray)
            }
        }
        .viewSize(avatarSize)
        .clipShape(Circle())
    }
}

struct AvatarImageView_Previews: PreviewProvider {
    static var previews: some View {
        AvatarImageView(
            url: nil,
            avatarSize: 32
        )
    }
}
