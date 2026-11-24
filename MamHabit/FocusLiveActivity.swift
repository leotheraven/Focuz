#if os(iOS)
import ActivityKit
import Foundation

@MainActor
final class FocusLiveActivity {
    private var task: Task<Void, Never>?
    func sync(_ session: FocusSession?) {
        // Serialize lifecycle changes so a late end cannot erase a newer activity.
        let previous = task
        task = Task {
            await previous?.value
            let activities = Activity<FocusActivityAttributes>.activities
            for activity in activities where activity.attributes.sessionID != session?.id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            guard let session else { return }
            let state = FocusActivityAttributes.ContentState(started: session.started, ends: session.ends,
                isBreak: session.isBreak, english: AppLanguage.isEnglish)
            let content = ActivityContent(state: state, staleDate: session.ends)
            if let existing = activities.first(where: { $0.attributes.sessionID == session.id }) {
                await existing.update(content)
            } else if ActivityAuthorizationInfo().areActivitiesEnabled {
                do { _ = try Activity.request(attributes: FocusActivityAttributes(sessionID: session.id), content: content, pushType: nil) }
                catch { print("Focuz Live Activity: \(error.localizedDescription)") }
            }
        }
    }
}
#endif
