import SwiftUI

public extension AttributedString {
    var urls: [URL] {
        runs[\.link].compactMap { link, _ in
            link?.absoluteURL
        }
    }
}
