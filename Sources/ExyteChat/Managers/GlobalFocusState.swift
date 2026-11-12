//
//  Created by Alex.M on 23.06.2022.
//

import Observation

@MainActor
@Observable
final class GlobalFocusState {
    var focus: Focusable?
}
