//
//  Created by Alex.M on 22.06.2022.
//

import Foundation
import Observation

@MainActor
@Observable
final class FullscreenMediaPagesViewModel {
    var attachments: [Attachment]
    var index: Int

    var videoPlaying = false
    var videoMuted = false

    var toggleVideoPlaying = {}
    var toggleVideoMuted = {}

    init(attachments: [Attachment], index: Int) {
        self.attachments = attachments
        self.index = index
    }
}
