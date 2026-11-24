import Foundation
import UserNotifications
import CoreFoundation

// Supplemental fast lock hint supplied by SpringBoard. The notification name
// is undocumented; UIKit lock/unlock evidence and persistence remain essential.
final class ScreenStateDetector {
    static let shared = ScreenStateDetector()
    static let didLock = Notification.Name("focuz.screen.didLock")
    private static let darwinName = "com.apple.springboard.lockcomplete" as CFString
    private init() {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(), { _, _, _, _, _ in
                // Never dereference an unretained observer on another thread.
                let detectedAt = Date()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: ScreenStateDetector.didLock, object: nil, userInfo: ["date": detectedAt])
                }
            }, Self.darwinName, nil, .deliverImmediately)
    }
    deinit {
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(), CFNotificationName(Self.darwinName), nil)
    }
}

enum FocuzNotificationSound {
    static let filename = "giot-nang.wav"
    static var sound: UNNotificationSound {
        UNNotificationSound(named: UNNotificationSoundName(rawValue: filename))
    }
}

// Keep the delegate alive: iOS otherwise silences notifications while Focuz is open.
final class SessionNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SessionNotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // willPresent means the user is already back in the foreground. Do not
        // play a delayed interruption warning after they have returned.
        if FocusInterruptionAlert.identifiers.contains(notification.request.identifier),
           notification.request.content.userInfo["presentInForeground"] as? Bool != true {
            completionHandler([])
            return
        }
        completionHandler([.banner, .list, .sound])
    }
}

struct SessionAlert: Equatable {
    var id: String
    var date: Date
    var isBreak: Bool
    static let identifiers = ["focuz.timer", "focuz.rest"]
    static func plans(for session: FocusSession, now: Date) -> [SessionAlert] {
        let alerts = [SessionAlert(id: "focuz.timer", date: session.ends, isBreak: session.isBreak)]
        return alerts.filter { $0.date > now }
    }
}

enum FocusInterruptionAlert {
    static let identifier = "focuz.interrupted"
    static let warningIdentifier = "focuz.departure.warning"
    static let identifiers = [identifier, warningIdentifier]
    static func warning(for session: FocusSession, departure: FocusDeparture, now: Date) -> UNNotificationRequest? {
        let date = departure.date.addingTimeInterval(FocusDeparture.warningDelay)
        guard departure.sessionID == session.id, departure.lockedAt == nil, departure.failedAt == nil,
              session.status == "running", session.strict, !session.isBreak,
              now < date, departure.deadline < session.ends else { return nil }
        let content = UNMutableNotificationContent()
        content.title = L("Quay lại Focus", "Return to Focus")
        content.body = L("Quay lại trong 5 giây để giữ phiên tập trung và phần thưởng.", "Return within 5 seconds to keep your focus session and rewards.")
        content.sound = .default
        content.userInfo = ["sessionID": session.id.uuidString]
        return UNNotificationRequest(identifier: warningIdentifier, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: date.timeIntervalSince(now), repeats: false))
    }
    static func request(for session: FocusSession, presentInForeground: Bool = false) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = L("Focus của bạn bị gián đoạn", "Your focus was interrupted")
        content.body = L("Phiên đã dừng và không nhận thưởng. Đồng hồ đã về \(session.minutes) phút. Mở Focuz để bắt đầu lại.", "The session ended without rewards. Your timer is reset to \(session.minutes) minutes. Open Focuz to start again.")
        content.sound = .default
        content.userInfo = ["sessionID": session.id.uuidString, "presentInForeground": presentInForeground]
        return UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    }
}
