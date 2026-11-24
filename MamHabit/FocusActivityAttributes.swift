#if os(iOS)
import ActivityKit
import Foundation

// Compiled into both the app and the Live Activity extension.
struct FocusActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var started: Date
        var ends: Date
        var isBreak: Bool
        var english: Bool
    }
    var sessionID: UUID
}
#endif
