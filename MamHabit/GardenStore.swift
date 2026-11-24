import SwiftUI
import UserNotifications
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

@MainActor
final class GardenStore: ObservableObject {
    @Published private(set) var engine: HabitEngine
    @Published var message: String?
    @Published var storageBlocked = false
    @Published var interruptedSession: FocusSession?
    private let url: URL
    private var reminderSync: Task<Void, Never>?
    private var departure: FocusDeparture? { engine.focusData.departure }
    private var departureTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var isForeground = true
    private var screenLockObserved = false
    private var interruptionAlertTask: Task<Void, Never>?
    private var sessionAlertTask: Task<Void, Never>?
    #if os(iOS)
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var backgroundGeneration = UUID()
    #endif
    #if os(iOS)
    private let liveActivity = FocusLiveActivity()
    #endif
    var today = Date()
    init(url: URL? = nil, preview: HabitEngine? = nil) {
        #if os(macOS)
        let demoURL = ProcessInfo.processInfo.environment["FOCUZ_DEMO_STATE"].map { URL(fileURLWithPath: $0) }
            ?? (Bundle.main.bundleIdentifier == "com.focuz.localdemo" ? Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("state.json") : nil)
        #else
        let demoURL: URL? = nil
        #endif
        self.url = url ?? demoURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MamHabit/state.json")
        if let preview { engine = preview; return }
        if FileManager.default.fileExists(atPath: self.url.path) {
            do {
                let data = try Data(contentsOf: self.url)
                engine = try HabitEngine(state: JSONDecoder().decode(GardenState.self, from: data)).validated()
                let plantMigrated = try engine.migratePlantProgress()
                if plantMigrated {
                    let backup = self.url.deletingLastPathComponent().appendingPathComponent("state-before-2.12.json")
                    if !FileManager.default.fileExists(atPath: backup.path) { try data.write(to: backup, options: .atomic) }
                }
                let historyMigrated = engine.migrateHistory()
                if plantMigrated || historyMigrated { try persist(engine) }
                if plantMigrated {
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: SessionAlert.identifiers)
                }
            } catch {
                engine = HabitEngine()
                storageBlocked = true
                message = L("Không đọc được dữ liệu đã lưu. Tệp gốc được giữ nguyên. Hãy khôi phục một bản sao lưu trong Cài đặt.", "Saved data could not be read. The original file is preserved. Restore a backup in Settings.")
            }
        } else { engine = .initial(at: Date()) }
        UNUserNotificationCenter.current().delegate = SessionNotificationDelegate.shared
        clearInterruptionAlert()
        resume()
    }
    @discardableResult
    func change(_ action: (inout HabitEngine) throws -> Void) -> Bool {
        guard !storageBlocked else { message = L("Hãy khôi phục bản sao lưu trước khi tiếp tục.", "Restore a backup before continuing."); return false }
        do {
            var next = engine
            try action(&next)
            try persist(next)
            let habitsChanged = engine.state.habits != next.state.habits
            engine = next
            if habitsChanged { syncHabitReminders() }
            return true
        } catch { message = error.localizedDescription; return false }
    }
    private func persist(_ next: HabitEngine) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(next.state)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    func refresh(now: Date = Date()) {
        today = now; engine.calendar.timeZone = .current
        #if os(iOS)
        if !screenLockObserved, departure?.lockedAt == nil, departure != nil, !UIApplication.shared.isProtectedDataAvailable {
            screenLocked(now: now)
            return
        }
        #endif
        if !screenLockObserved, let leaving = departure,
           leaving.shouldInterrupt(engine.focusData.active, now: now), let session = engine.focusData.active {
            if change({ _ = $0.resolveFocusDeparture(now: now) }) {
                departureTask?.cancel()
                clearInterruptionAlert()
                sessionAlertTask?.cancel()
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: SessionAlert.identifiers)
                syncLiveActivity()
                if !isForeground {
                    queueInterruptionAlert(FocusInterruptionAlert.request(for: session), endingBackgroundTask: true) {
                        self.departure?.sessionID == session.id && self.departure?.failedAt != nil
                    }
                }
                finishBackgroundTask()
            }
        }
        if let session = engine.focusData.active, today >= session.ends,
           !(screenLockObserved && departure != nil && departure?.lockedAt == nil) {
            if change({ try $0.finishFocus(now: today) }) {
                departureTask?.cancel()
                clearInterruptionAlert()
                finishBackgroundTask()
                syncLiveActivity()
            }
        }
        if isForeground { queueFailureNotice() }
        objectWillChange.send()
    }
    // Inactive alone (Control Center, permission sheet, incoming-call banner)
    // does not forfeit a session. Ask for time before UIKit suspends the app.
    func prepareForBackground() {
        guard let session = engine.focusData.active, session.strict, !session.isBreak else { return }
        #if os(iOS)
        guard backgroundTask == .invalid else { return }
        let generation = UUID()
        backgroundGeneration = generation
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Focus interruption grace") { [weak self] in
            Task { @MainActor in
                guard let self, self.backgroundGeneration == generation else { return }
                self.backgroundTimeExpired()
            }
        }
        #endif
    }
    func backgroundFocus(now: Date = Date()) {
        isForeground = false
        refresh(now: now)
        guard let session = engine.focusData.active, session.strict, !session.isBreak,
              now < session.ends else { finishBackgroundTask(); return }
        prepareForBackground()
        if departure == nil, !change({ _ = $0.leaveFocus(at: now) }) { finishBackgroundTask(); return }
        if screenLockObserved { screenLocked(now: now); return }
        #if os(iOS)
        if !UIApplication.shared.isProtectedDataAvailable { screenLocked(now: now); return }
        #endif
        guard let leaving = departure, leaving.lockedAt == nil, leaving.failedAt == nil else { finishBackgroundTask(); return }
        if session.ends > leaving.deadline {
            sessionAlertTask?.cancel()
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: SessionAlert.identifiers)
        }
        if let warning = FocusInterruptionAlert.warning(for: session, departure: leaving, now: now) {
            queueInterruptionAlert(warning) {
                self.departure?.sessionID == session.id && self.departure?.lockedAt == nil
                    && self.departure?.failedAt == nil && self.engine.focusData.active?.id == session.id && !self.isForeground
            }
        }
        departureTask?.cancel()
        departureTask = Task {
            do { try await Task.sleep(for: .seconds(max(0, leaving.deadline.timeIntervalSince(now)))) }
            catch { return }
            guard !Task.isCancelled, departure?.sessionID == leaving.sessionID else { return }
            refresh()
        }
    }
    func screenLocked(now: Date = Date()) {
        if let leaving = departure, now < leaving.date { return }
        let currentSessionID = engine.focusData.active?.id ?? (departure?.failedAt != nil ? departure?.sessionID : nil)
        screenLockObserved = true
        departureTask?.cancel()
        noticeTask?.cancel(); noticeTask = nil
        interruptedSession = nil
        if departure != nil { _ = change { _ = $0.recordFocusLock(at: now) } }
        finishBackgroundTask()
        clearInterruptionAlert()
        refresh(now: now)
        syncLiveActivity()
        if let active = engine.focusData.active {
            Task { await scheduleSessionAlerts(active, now: now, allowCompleted: true) }
        } else if let completed = engine.focusData.sessions.last, completed.id == currentSessionID,
                  completed.status == "done", completed.ends <= now {
            Task { await scheduleSessionAlerts(completed, now: now, allowCompleted: true) }
        }
    }
    // This signal is evidence of a lock/unlock cycle even if UIKit delivered
    // the "will become unavailable" signal too late or the app was suspended.
    func screenUnlocked(now: Date = Date()) {
        screenLocked(now: now)
        if isForeground { resume(now: now) }
    }
    func backgroundTimeExpired(now: Date = Date()) {
        departureTask?.cancel()
        // Never treat iOS reclaiming background time as a user interruption.
        // The saved departure is reconciled by absolute dates on next resume.
        finishBackgroundTask()
        refresh(now: now)
    }
    private func finishBackgroundTask() {
        #if os(iOS)
        if backgroundTask != .invalid {
            let task = backgroundTask
            backgroundTask = .invalid
            backgroundGeneration = UUID()
            UIApplication.shared.endBackgroundTask(task)
        }
        #endif
    }
    private func queueInterruptionAlert(_ request: UNNotificationRequest, endingBackgroundTask: Bool = false,
                                        eligible: @escaping () -> Bool) {
        let previous = interruptionAlertTask
        previous?.cancel()
        #if os(iOS)
        let taskToEnd = endingBackgroundTask ? backgroundTask : .invalid
        if endingBackgroundTask { backgroundTask = .invalid }
        #endif
        interruptionAlertTask = Task {
            #if os(iOS)
            defer { if taskToEnd != .invalid { UIApplication.shared.endBackgroundTask(taskToEnd) } }
            #endif
            await previous?.value
            guard !Task.isCancelled, eligible() else { return }
            do { try await UNUserNotificationCenter.current().add(request) }
            catch { if !Task.isCancelled { message = L("Chưa gửi được cảnh báo Focus. Kiểm tra quyền thông báo Focuz.", "Focus alerts are unavailable. Check Focuz notification permissions.") } }
            if Task.isCancelled || !eligible() {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [request.identifier])
            }
        }
    }
    private func queueFailureNotice() {
        guard isForeground, let leaving = departure, leaving.failedAt != nil, !leaving.noticeShown,
              let session = engine.focusData.sessions.last, session.id == leaving.sessionID,
              interruptedSession == nil, noticeTask == nil else { return }
        noticeTask = Task {
            // Let the unlock notification queued beside didBecomeActive arrive
            // before presenting a failure for what may have been a locked phone.
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard !Task.isCancelled, isForeground, departure?.sessionID == session.id,
                  departure?.failedAt != nil, departure?.noticeShown == false else { noticeTask = nil; return }
            if change({ engine in var data = engine.focusData; data.departure?.noticeShown = true; engine.state.focus = data }) {
                interruptedSession = session
                queueInterruptionAlert(FocusInterruptionAlert.request(for: session, presentInForeground: true)) {
                    self.interruptedSession?.id == session.id && self.departure?.failedAt != nil
                }
            }
            noticeTask = nil
        }
    }
    func dismissFocusInterruption() {
        noticeTask?.cancel(); noticeTask = nil
        interruptedSession = nil
    }
    private func clearInterruptionAlert() {
        interruptionAlertTask?.cancel()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: FocusInterruptionAlert.identifiers)
        center.removeDeliveredNotifications(withIdentifiers: FocusInterruptionAlert.identifiers)
    }
    func resume(now: Date = Date()) {
        isForeground = true
        departureTask?.cancel()
        finishBackgroundTask()
        #if os(iOS)
        if !UIApplication.shared.isProtectedDataAvailable { screenLocked(now: now) }
        #endif
        clearInterruptionAlert()
        if screenLockObserved, departure != nil { _ = change { _ = $0.recordFocusLock(at: now) } }
        if departure != nil { _ = change { $0.returnToFocus(at: now) } }
        screenLockObserved = false
        refresh(now: now)
        syncHabitReminders()
        syncLiveActivity()
        if let active = engine.focusData.active {
            Task { await scheduleSessionAlerts(active, now: now) }
        }
    }
    func beginFocus(minutes: Int, isBreak: Bool = false) async {
        guard engine.focusData.active == nil else { return }
        dismissFocusInterruption()
        clearInterruptionAlert()
        await enableFocusNotifications(showMessage: false)
        // Another tap may have started a session during the authorization sheet.
        guard engine.focusData.active == nil else { return }
        let now = Date()
        today = now
        if change({ try $0.startFocus(minutes: minutes, strict: true, isBreak: isBreak, now: now) }),
           let active = engine.focusData.active {
            syncLiveActivity()
            await scheduleSessionAlerts(active, now: now)
        }
    }
    private func scheduleSessionAlerts(_ active: FocusSession, now: Date, allowCompleted: Bool = false) async {
        func stillEligible() -> Bool {
            let allowsCompletion = departure == nil || departure?.lockedAt != nil
                || (departure.map { active.ends <= $0.deadline } ?? false)
            return allowsCompletion && (engine.focusData.active?.id == active.id || (allowCompleted && engine.focusData.active == nil && engine.focusData.sessions.contains { $0.id == active.id && $0.status == "done" }))
        }
        guard stillEligible() else { return }
        let plans = allowCompleted && active.ends <= now
            ? [SessionAlert(id: "focuz.timer", date: now.addingTimeInterval(1), isBreak: active.isBreak)]
            : SessionAlert.plans(for: active, now: now)
        let previous = sessionAlertTask
        previous?.cancel()
        let task = Task {
            // A stale add must finish its cleanup before a newer timer is added.
            await previous?.value
            guard !Task.isCancelled, stillEligible() else { return }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: SessionAlert.identifiers)
            do {
                for alert in plans {
                    guard !Task.isCancelled, stillEligible() else { return }
                    let content = UNMutableNotificationContent()
                    content.title = alert.isBreak ? L("Hết giờ Rest", "Rest finished") : L("Focus hoàn tất", "Focus complete")
                    content.body = alert.isBreak ? L("Sẵn sàng cho phiên tập trung tiếp theo.", "Ready for your next focus session.")
                        : L("+\(active.minutes) EXP cây · +\(active.minutes) xu. Mở Focuz để bắt đầu Rest.", "+\(active.minutes) plant EXP · +\(active.minutes) coins. Open Focuz to start rest.")
                    content.sound = FocuzNotificationSound.sound
                    try await center.add(UNNotificationRequest(identifier: alert.id, content: content,
                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, alert.date.timeIntervalSinceNow), repeats: false)))
                    if Task.isCancelled || !stillEligible() {
                        center.removePendingNotificationRequests(withIdentifiers: SessionAlert.identifiers)
                        return
                    }
                }
            } catch { if !Task.isCancelled { message = L("Chưa gửi được thông báo; kiểm tra quyền thông báo Focuz trong Cài đặt.", "Alerts are unavailable; check Focuz notification permissions in Settings.") } }
        }
        sessionAlertTask = task
        await task.value
    }
    private func syncLiveActivity() {
        #if os(iOS)
        liveActivity.sync(engine.focusData.active)
        #endif
    }
    func authorizeHabitReminders() async -> Bool {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            if !allowed { message = L("Hãy cho phép thông báo Focuz trong Cài đặt thiết bị để đặt giờ nhắc.", "Allow Focuz notifications in device Settings to set a reminder.") }
            return allowed
        } catch {
            message = L("Đã giữ giờ nhắc. Chưa được phép gửi thông báo trên thiết bị này; kiểm tra quyền thông báo của Focuz trong Cài đặt.", "Reminder time is saved. Notifications are unavailable on this device; check Focuz notification permissions in Settings.")
            return false
        }
    }
    func syncHabitReminders() {
        let previous = reminderSync
        previous?.cancel()
        let plans = engine.habitReminderPlans
        reminderSync = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            guard !Task.isCancelled else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("focuz.habit.") }.map(\.identifier))
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            do {
                for plan in plans {
                    guard !Task.isCancelled else { return }
                    let content = UNMutableNotificationContent()
                    content.title = L("Đến giờ thực hiện thói quen", "Habit reminder")
                    content.body = plan.title
                    content.sound = FocuzNotificationSound.sound
                    var components = DateComponents()
                    components.weekday = plan.weekday; components.hour = plan.hour; components.minute = plan.minute
                    try await center.add(UNNotificationRequest(identifier: plan.id, content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
                }
            } catch { message = L("Chưa đặt được lời nhắc: \(error.localizedDescription)", "Could not schedule reminder: \(error.localizedDescription)") }
        }
    }
    func enableFocusNotifications(showMessage: Bool = true) async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound])
            if showMessage || !allowed { message = allowed ? L("Đã bật thông báo kết thúc phiên.", "Session notifications enabled.") : L("Hãy cho phép thông báo Focuz trong Cài đặt iPhone.", "Allow Focuz notifications in device Settings.") }
        } catch { message = error.localizedDescription }
    }
    func skipRest() {
        _ = change { engine in var data = engine.focusData; data.awaitingRest = false; engine.state.focus = data }
    }
    func cancelFocus() {
        departureTask?.cancel()
        dismissFocusInterruption()
        finishBackgroundTask()
        clearInterruptionAlert()
        refresh()
        if change({ try $0.finishFocus(now:Date(),cancel:true) }) {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: SessionAlert.identifiers)
            syncLiveActivity()
        }
    }
    func check(_ habit: Habit) {
        var earned = false
        if change({ earned = try $0.check(habit.id, at: Date()) }) {
            feedback()
            if earned { message = L("+10 xu.", "+10 coins.") }
        }
    }
    func fertilize(_ quote: FertilizerQuote) {
        if change({ try $0.fertilize(quote, at: Date()) }) {
            feedback()
            let name = HabitEngine.gardenItems.first { $0.id == quote.plantID }?.name ?? "Cây xanh"
            message = L("Đã bón phân cho \(name): +\(quote.xp) XP · −\(quote.cost) xu.", "Fertilized \(AppLanguage.text(name)): +\(quote.xp) XP · −\(quote.cost) coins.")
        }
    }
    func restore(_ data: Data) throws {
        guard data.count <= 20_000_000 else { throw GardenError.invalid(L("Tệp quá lớn. Hãy chọn bản sao lưu Mầm dưới 20 MB.", "Choose a Focuz backup smaller than 20 MB.")) }
        var next = try HabitEngine(state: JSONDecoder().decode(GardenState.self, from: data)).validated()
        try next.migratePlantProgress()
        next.migrateHistory()
        // Keep per-habit times. Scheduling still requires notification permission on this device.
        next.state.reminderEnabled = false
        if next.focusData.active != nil { try next.finishFocus(now: Date(), cancel: true) }
        var focus = next.focusData; focus.departure = nil; next.state.focus = focus
        try persist(next)
        departureTask?.cancel()
        dismissFocusInterruption()
        finishBackgroundTask()
        engine = next
        storageBlocked = false
        clearInterruptionAlert()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["mam.daily"] + SessionAlert.identifiers)
        syncHabitReminders()
        syncLiveActivity()
        message = L("Đã khôi phục dữ liệu. Bạn có thể bật lại nhắc nhở.", "Data restored. You can enable reminders again.")
    }
    func setReminder(enabled: Bool, time: Date) async {
        let center = UNUserNotificationCenter.current()
        if !enabled {
            if change({ $0.state.reminderEnabled = false }) { center.removePendingNotificationRequests(withIdentifiers: ["mam.daily"]) }
            return
        }
        do {
            let allowed = try await center.requestAuthorization(options: [.alert, .sound])
            guard allowed else { message = L("Thông báo chưa được cho phép. Bạn có thể bật trong Cài đặt của thiết bị.", "Notifications are disabled. Enable them in device Settings."); return }
            let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
            let content = UNMutableNotificationContent()
            content.title = L("Đến giờ chăm Mầm", "Daily habits")
            content.body = L("Mở Focuz để xem thói quen hôm nay.", "Open Focuz to check your habits.")
            content.sound = FocuzNotificationSound.sound
            try await center.add(UNNotificationRequest(identifier: "mam.daily", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)))
            if !change({ $0.state.reminderEnabled = true; $0.state.reminderHour = parts.hour ?? 20; $0.state.reminderMinute = parts.minute ?? 0 }) {
                center.removePendingNotificationRequests(withIdentifiers: ["mam.daily"])
            }
        } catch { message = L("Chưa đặt được lời nhắc: \(error.localizedDescription)", "Could not set reminder: \(error.localizedDescription)") }
    }
    private func feedback() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(state: GardenState) { data = (try? JSONEncoder().encode(state)) ?? Data() }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
