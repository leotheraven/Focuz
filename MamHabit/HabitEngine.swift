import Foundation

struct Habit: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var symbol: String
    var color: String
    var target: Int
    var unit: String
    var weekdays: Set<Int> = Set(1...7)
    var created: String
    var archived = false
    var deleted: Bool? = nil // Tombstone retains earned rewards and backup compatibility.
    var reminder: HabitReminder? = nil
}

struct HabitReminder: Codable, Equatable {
    var hour: Int
    var minute: Int
    var isValid: Bool { (0...23).contains(hour) && (0...59).contains(minute) }
    var label: String { String(format: "%02d:%02d", hour, minute) }
}

// Repeating weekly requests leave room for the daily reminder and both timer alerts.
struct HabitReminderPlan: Equatable {
    var id: String
    var title: String
    var weekday: Int
    var hour: Int
    var minute: Int
}

struct CheckIn: Codable, Identifiable {
    var id: String { "\(habitID.uuidString)|\(day)" }
    var habitID: UUID
    var day: String
    var count: Int
    var target: Int
    var title: String? = nil
    var completedAt: Date? = nil
    var rewarded: Bool = false
    var complete: Bool { count >= target }
}

struct Reward: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var symbol: String
    var cost: Int
    var decoration: Bool = false
    var custom: Bool = false
}

struct Redemption: Codable, Identifiable {
    var id = UUID()
    var rewardID: String
    var title: String
    var cost: Int
    var date: Date
}

struct Fertilization: Codable, Identifiable {
    var id = UUID()
    var plantID: String
    var xp: Int
    var cost: Int
    var date: Date
    var growthRevision: Int
    var productID = "fertilizer-25-v1"
}

struct FertilizerQuote: Equatable {
    var plantID: String
    var xp: Int
    var cost: Int
}

struct GardenState: Codable {
    var focus: FocusState? = nil
    var version = 2
    var habits: [Habit] = []
    var checkIns: [CheckIn] = []
    var chests: Set<String> = []
    var redemptions: [Redemption] = []
    var fertilizations: [Fertilization]? = nil
    var olderRewardSpending: Int? = nil
    var olderUnlocks: Set<String>? = nil
    var customRewards: [Reward] = []
    var equipped = "original"
    var petName = "Mầm"
    var reminderEnabled = false
    var reminderHour = 20
    var reminderMinute = 0
}

enum GardenError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

struct HabitEngine {
    static let historyLimit = 20

    var state: GardenState
    var calendar: Calendar
    init(state: GardenState = GardenState(), calendar: Calendar = .current) {
        self.state = state
        var stable = Calendar(identifier: .gregorian)
        stable.timeZone = calendar.timeZone
        self.calendar = stable
    }
    func day(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let result = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])), day(result) == key else { return nil }
        return result
    }
    func scheduled(_ habit: Habit, on date: Date) -> Bool {
        habit.deleted != true && !habit.archived && habit.created <= day(date) && habit.weekdays.contains(calendar.component(.weekday, from: date))
    }
    func habits(on date: Date) -> [Habit] { state.habits.filter { scheduled($0, on: date) } }
    func entry(_ habit: Habit, on date: Date) -> CheckIn? {
        state.checkIns.first { $0.habitID == habit.id && $0.day == day(date) }
    }
    func completed(_ habit: Habit, on date: Date) -> Bool { entry(habit, on: date)?.complete ?? false }
    var completedCount: Int { state.checkIns.filter(\.complete).count }
    var totalPlantXP: Int { focusData.growth.values.reduce(0) { $0 + $1.totalPoints } }
    private var coinsBeforeOlderSpending: Int { state.checkIns.filter(\.rewarded).count * TaskReward.habit.coins + state.chests.count * 25 + focusCoins - state.redemptions.reduce(0) { $0 + $1.cost } - fertilizerUses.reduce(0) { $0 + $1.cost } }
    var coins: Int { coinsBeforeOlderSpending - (state.olderRewardSpending ?? 0) }
    var owned: Set<String> { Set(state.redemptions.map(\.rewardID)).union(state.olderUnlocks ?? []) }
    var recentActivity: [CheckIn] {
        state.checkIns.reversed().filter { $0.complete && $0.title != nil }.sorted {
            if $0.day != $1.day { return $0.day > $1.day }
            return ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
    }
    @discardableResult
    mutating func migrateHistory() -> Bool {
        guard state.version == 1 else { return false }
        pruneActivity()
        pruneRewards()
        state.version = 2
        return true
    }
    private mutating func pruneActivity() {
        let keep = Set(recentActivity.prefix(Self.historyLimit).map(\.id))
        // Older check-ins still drive calendar counts, streaks and once-per-day rewards.
        for index in state.checkIns.indices where state.checkIns[index].title != nil && !keep.contains(state.checkIns[index].id) {
            state.checkIns[index].title = nil
            state.checkIns[index].completedAt = nil
        }
    }
    func canClaimChest(on now: Date) -> Bool {
        let today = habits(on: now)
        return !today.isEmpty && today.allSatisfy { completed($0, on: now) } && !state.chests.contains(day(now))
    }
    mutating func check(_ id: UUID, at now: Date) throws -> Bool {
        guard let habit = state.habits.first(where: { $0.id == id }), scheduled(habit, on: now) else { throw GardenError.invalid(L("Thói quen này không có lịch hôm nay.", "This habit is not scheduled today.")) }
        let key = day(now)
        if state.checkIns.firstIndex(where: { $0.habitID == id && $0.day == key }) == nil {
            state.checkIns.append(CheckIn(habitID: id, day: key, count: 0, target: habit.target))
        }
        let index = state.checkIns.firstIndex { $0.habitID == id && $0.day == key }!
        guard !state.checkIns[index].complete else { return false }
        state.checkIns[index].count += 1
        guard state.checkIns[index].complete else { return false }
        let earned = !state.checkIns[index].rewarded
        state.checkIns[index].rewarded = true
        state.checkIns[index].title = habit.title
        state.checkIns[index].completedAt = now
        pruneActivity()
        return earned
    }
    mutating func undo(_ id: UUID, at now: Date) {
        guard let index = state.checkIns.firstIndex(where: { $0.habitID == id && $0.day == day(now) }) else { return }
        state.checkIns[index].count = max(0, state.checkIns[index].count - 1)
        state.checkIns[index].title = nil
        state.checkIns[index].completedAt = nil
        // A reward is earned once per habit per local day. Editing progress cannot mint coins.
    }
    mutating func claimChest(at now: Date) throws {
        guard canClaimChest(on: now) else { throw GardenError.invalid(L("Hoàn thành tất cả thói quen hôm nay để mở rương.", "Complete today's habits to claim the daily reward.")) }
        state.chests.insert(day(now))
    }
    var habitReminderPlans: [HabitReminderPlan] {
        state.habits.filter { !$0.archived && $0.deleted != true && $0.reminder != nil }
            .flatMap { habit in habit.weekdays.sorted().map { weekday in
                HabitReminderPlan(id: "focuz.habit.\(habit.id.uuidString).\(weekday)", title: habit.title,
                                  weekday: weekday, hour: habit.reminder!.hour, minute: habit.reminder!.minute)
            } }
    }
    mutating func saveHabit(_ habit: Habit) throws {
        guard habit.deleted != true, !state.habits.contains(where: { $0.id == habit.id && $0.deleted == true }) else { throw GardenError.invalid(L("Thói quen đã bị xóa.", "This habit has been deleted.")) }
        guard !habit.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, habit.title.count <= 70,
              (1...20).contains(habit.target), !habit.weekdays.isEmpty, habit.weekdays.isSubset(of: Set(1...7)),
              habit.unit.count <= 20, habit.reminder?.isValid != false else { throw GardenError.invalid(L("Nhập tên, mục tiêu từ 1–20 và chọn ít nhất một ngày.", "Enter a name, a target of 1–20, and at least one day.")) }
        let others = state.habits.filter { $0.id != habit.id && $0.deleted != true && $0.reminder != nil }
        let count = others.reduce(0) { $0 + $1.weekdays.count } + (habit.reminder == nil ? 0 : habit.weekdays.count)
        guard count <= 60 else { throw GardenError.invalid(L("Đã đạt giới hạn 60 lịch nhắc trong tuần. Giảm ngày nhắc hoặc tắt lời nhắc của một thói quen khác.", "The 60 weekly reminder limit is reached. Reduce reminder days or disable another habit reminder.")) }
        if let index = state.habits.firstIndex(where: { $0.id == habit.id }) { state.habits[index] = habit }
        else { state.habits.append(habit) }
    }
    mutating func archive(_ id: UUID) {
        pauseHabit(id, paused: true)
    }
    mutating func pauseHabit(_ id: UUID, paused: Bool) {
        if let index = state.habits.firstIndex(where: { $0.id == id && $0.deleted != true }) { state.habits[index].archived = paused }
    }
    mutating func deleteHabit(_ id: UUID) {
        if let index = state.habits.firstIndex(where: { $0.id == id }) {
            state.habits[index].deleted = true
            state.habits[index].archived = true
        }
    }
    func streak(_ habit: Habit, at now: Date) -> Int {
        var cursor = calendar.startOfDay(for: now)
        var count = 0
        for offset in 0..<36600 {
            guard day(cursor) >= habit.created else { break }
            if habit.weekdays.contains(calendar.component(.weekday, from: cursor)) {
                if completed(habit, on: cursor) { count += 1 }
                else if offset > 0 { break }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
    static let catalog = [
        Reward(id: "terracotta", title: "Chậu đất nung", detail: "Một chiếc chậu ấm áp cho Mầm", symbol: "cup.and.saucer.fill", cost: 180, decoration: true),
        Reward(id: "night", title: "Vườn đom đóm", detail: "Thắp sáng góc vườn buổi tối", symbol: "moon.stars.fill", cost: 360, decoration: true),
        Reward(id: "rainbow", title: "Vườn cầu vồng", detail: "Một khoảng trời đầy sắc màu", symbol: "rainbow", cost: 600, decoration: true),
        Reward(id: "coffee", title: "Một ly yêu thích", detail: "Dành thời gian thưởng thức thật chậm", symbol: "mug.fill", cost: 240),
        Reward(id: "movie", title: "Một tối xem phim", detail: "Chọn bộ phim bạn đã để dành", symbol: "popcorn.fill", cost: 450)
    ]
    var rewards: [Reward] { Self.catalog + state.customRewards }
    mutating func redeem(_ id: String, at now: Date) throws {
        guard let reward = rewards.first(where: { $0.id == id }) else { throw GardenError.invalid(L("Không tìm thấy phần thưởng.", "Reward not found.")) }
        guard !reward.decoration || !owned.contains(id) else { state.equipped = id; return }
        guard coins >= reward.cost else { throw GardenError.invalid(L("Bạn cần thêm \(reward.cost - coins) xu.", "You need \(reward.cost - coins) more coins.")) }
        state.redemptions.append(Redemption(rewardID: id, title: reward.title, cost: reward.cost, date: now))
        pruneRewards()
        if reward.decoration { state.equipped = id }
    }
    mutating func addReward(title: String, cost: Int) throws {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 70, (10...10000).contains(cost) else { throw GardenError.invalid(L("Nhập tên quà và giá từ 10–10.000 xu.", "Enter a reward name and a cost of 10–10,000 coins.")) }
        state.customRewards.append(Reward(id: UUID().uuidString, title: cleaned, detail: "Phần thưởng bạn tự dành cho mình", symbol: "gift.fill", cost: cost, custom: true))
    }
    func validated() throws -> HabitEngine {
        guard (1...2).contains(state.version), state.habits.count <= 500, state.checkIns.count <= 200000,
              state.redemptions.count <= 100000, state.customRewards.count <= 500,
              fertilizerUses.count <= 100000, fertilizerUses.allSatisfy({ (1...50).contains($0.cost) }),
              Set(state.habits.map(\.id)).count == state.habits.count,
              Set(state.checkIns.map(\.id)).count == state.checkIns.count,
              Set(rewards.map(\.id)).count == rewards.count,
              Set(state.redemptions.map(\.id)).count == state.redemptions.count,
              (0...23).contains(state.reminderHour), (0...59).contains(state.reminderMinute),
              !state.petName.isEmpty, state.petName.count <= 24 else { throw GardenError.invalid(L("Tệp sao lưu không hợp lệ hoặc thuộc phiên bản mới hơn.", "This backup is invalid or from a newer version.")) }
        for habit in state.habits {
            var check = HabitEngine(calendar: calendar)
            var validHabit = habit; validHabit.deleted = nil
            try check.saveHabit(validHabit)
            guard date(habit.created) != nil else { throw GardenError.invalid(L("Ngày tạo không hợp lệ.", "Invalid creation date.")) }
        }
        let ids = Set(state.habits.map(\.id))
        for entry in state.checkIns {
            guard ids.contains(entry.habitID), date(entry.day) != nil, (1...20).contains(entry.target),
                  (0...entry.target).contains(entry.count), !entry.complete || entry.rewarded else { throw GardenError.invalid(L("Lịch sử không hợp lệ.", "Invalid history.")) }
        }
        for reward in state.customRewards {
            guard reward.custom, !reward.decoration, (10...10000).contains(reward.cost), !reward.title.isEmpty, reward.title.count <= 70 else { throw GardenError.invalid(L("Phần thưởng không hợp lệ.", "Invalid reward.")) }
        }
        try validateFocus()
        let olderSpending = state.olderRewardSpending ?? 0
        guard state.chests.allSatisfy({ date($0) != nil }), state.redemptions.allSatisfy({ (10...10000).contains($0.cost) }),
              olderSpending >= 0, olderSpending <= coinsBeforeOlderSpending,
              (state.olderUnlocks ?? []).isSubset(of: Self.unlockableRewardIDs),
              state.version == 1 || (recentActivity.count <= Self.historyLimit && state.redemptions.count + fertilizerUses.count <= Self.historyLimit)
        else { throw GardenError.invalid(L("Số dư hoặc lịch sử thưởng không hợp lệ.", "Invalid balance or reward history.")) }
        if state.equipped != "original" {
            guard Self.catalog.contains(where: { $0.id == state.equipped && $0.decoration }), owned.contains(state.equipped) else { throw GardenError.invalid(L("Đồ trang trí chưa được mở khóa.", "This decoration is locked.")) }
        }
        guard state.habits.filter({ $0.deleted != true && $0.reminder != nil }).reduce(0, { $0 + $1.weekdays.count }) <= 60 else {
            throw GardenError.invalid(L("Quá nhiều lịch nhắc. Giới hạn là 60 lịch mỗi tuần.", "Too many reminders. The limit is 60 weekly schedules."))
        }
        return self
    }
    static func initial(at now: Date) -> HabitEngine {
        var engine = HabitEngine()
        let key = engine.day(now)
        engine.state.habits = [
            Habit(title: "Uống đủ nước", symbol: "drop.fill", color: "blue", target: 6, unit: "ly", created: key),
            Habit(title: "Đọc 10 trang sách", symbol: "book.closed.fill", color: "purple", target: 1, unit: "lần", created: key),
            Habit(title: "Vận động 15 phút", symbol: "figure.walk", color: "orange", target: 1, unit: "lần", created: key)
        ]
        return engine
    }
}


struct TaskReward {
    let coins: Int
    let xp: Int
    static let habit = TaskReward(coins: 10, xp: 0)
    static func focus(minutes: Int) -> TaskReward { TaskReward(coins: minutes, xp: minutes) }
}

struct FocusSession: Codable, Identifiable {
    var id = UUID()
    var started: Date
    var ends: Date
    var minutes: Int
    var habitID: UUID? = nil // Decode old sessions only; never auto-check a habit.
    var plantID: String
    var strict: Bool
    var isBreak: Bool = false
    var status = "running"
    // Completed sessions before build 9 have no field and earned 2 XP/minute.
    // Record the actual award for new sessions so updates never reprice history.
    var earnedXP: Int? = nil
    var endedAt: Date? = nil
    var completedSeconds: Int? = nil
}

struct FocusDeparture: Codable, Equatable {
    static let gracePeriod: TimeInterval = 10
    static let warningDelay: TimeInterval = 5
    let sessionID: UUID
    let date: Date
    var lockedAt: Date? = nil
    var failedAt: Date? = nil
    var returnedAt: Date? = nil
    var noticeShown = false
    var deadline: Date { date.addingTimeInterval(Self.gracePeriod) }
    func shouldInterrupt(_ session: FocusSession?, now: Date) -> Bool {
        guard let session else { return false }
        return lockedAt == nil && failedAt == nil && now >= deadline && session.status == "running"
            && session.id == sessionID && session.strict && !session.isBreak && deadline < session.ends
    }
}
struct PlantGrowth: Codable {
    // Decode legacy growth so old backups can be validated before migration.
    var water = 0
    var sunlight = 0
    var points: Int? = nil
    var totalPoints: Int { points ?? (water * 20 + sunlight * 2) }
}
struct FocusState: Codable {
    // Older revisions reset once for the 100-level garden in version 2.12.
    var growthRevision: Int? = HabitEngine.plantProgressRevision
    var preferredMinutes: Int? = nil
    var selectedPlant = "sprout"
    var growth: [String: PlantGrowth] = [:]
    var sessions: [FocusSession] = []
    var active: FocusSession?
    var departure: FocusDeparture? = nil
    var awaitingRest: Bool? = nil
    var decorations: [String: String] = [:]
}
struct GardenItem: Identifiable {
    var id: String
    var name: String
    var symbol: String
    var cost: Int
    var category: String
}
extension HabitEngine {
    static let plantProgressRevision = 3
    static let fertilizerPackXP = 25
    static let fertilizerCoinsPerXP = 2
    var fertilizerUses: [Fertilization] { state.fertilizations ?? [] }
    private static let unlockableRewardIDs = Set(
        catalog.filter(\.decoration).map(\.id) + legacyGardenItems.filter { $0.cost > 0 }.map(\.id)
    )
    private mutating func pruneRewards() {
        guard state.redemptions.count + fertilizerUses.count > Self.historyLimit else { return }
        let purchases = state.redemptions.map { (id: $0.id, date: $0.date, fertilizer: false) }
        let fertilizations = fertilizerUses.map { (id: $0.id, date: $0.date, fertilizer: true) }
        let excess = (purchases + fertilizations).reversed().sorted { $0.date > $1.date }.dropFirst(Self.historyLimit)
        let oldPurchases = Set(excess.filter { !$0.fertilizer }.map(\.id))
        let oldFertilizations = Set(excess.filter(\.fertilizer).map(\.id))
        let removedPurchases = state.redemptions.filter { oldPurchases.contains($0.id) }
        let removedFertilizations = fertilizerUses.filter { oldFertilizations.contains($0.id) }
        let spending = removedPurchases.reduce(0) { $0 + $1.cost } + removedFertilizations.reduce(0) { $0 + $1.cost }
        state.olderRewardSpending = (state.olderRewardSpending ?? 0) + spending
        let unlocks = Set(removedPurchases.map(\.rewardID)).intersection(Self.unlockableRewardIDs)
        state.olderUnlocks = (state.olderUnlocks ?? []).union(unlocks)
        state.redemptions.removeAll { oldPurchases.contains($0.id) }
        state.fertilizations?.removeAll { oldFertilizations.contains($0.id) }
    }
    func fertilizerQuote(for plantID: String? = nil) -> FertilizerQuote? {
        let id = plantID ?? focusData.selectedPlant
        guard Self.gardenItems.contains(where: { $0.id == id && $0.category == "Cây" }),
              id == "sprout" || owned.contains(id) else { return nil }
        let remaining = Self.maxPlantPoints - (focusData.growth[id]?.totalPoints ?? 0)
        guard remaining > 0 else { return nil }
        let xp = min(Self.fertilizerPackXP, remaining)
        return FertilizerQuote(plantID: id, xp: xp, cost: xp * Self.fertilizerCoinsPerXP)
    }
    mutating func fertilize(_ quote: FertilizerQuote, at now: Date) throws {
        guard focusData.growthRevision == Self.plantProgressRevision,
              fertilizerQuote(for: quote.plantID) == quote else {
            throw GardenError.invalid(L("Tiến độ cây đã thay đổi hoặc cây đã đạt cấp tối đa. Hãy chọn lại phân bón.", "Plant progress changed or the plant is at max level. Select fertilizer again."))
        }
        guard coins >= quote.cost else { throw GardenError.invalid(L("Bạn chưa đủ xu.", "Not enough coins.")) }
        state.fertilizations = fertilizerUses + [Fertilization(plantID: quote.plantID, xp: quote.xp, cost: quote.cost,
                                                              date: now, growthRevision: Self.plantProgressRevision)]
        pruneRewards()
        nourish(points: quote.xp, plant: quote.plantID)
    }
    @discardableResult
    mutating func migratePlantProgress() throws -> Bool {
        guard (focusData.growthRevision ?? 0) < Self.plantProgressRevision else { return false }
        // Cancel an old in-flight session before resetting, so it cannot add
        // pre-update EXP to the new garden when the app next refreshes.
        if focusData.active != nil { try finishFocus(now: Date(), cancel: true) }
        var data = focusData
        data.growth = [:]
        data.growthRevision = Self.plantProgressRevision
        data.awaitingRest = false
        data.departure = nil
        state.focus = data
        return true
    }
    var focusData: FocusState { state.focus ?? FocusState() }
    var focusCoins: Int { focusData.sessions.filter { $0.status == "done" && !$0.isBreak }.reduce(0) { $0 + TaskReward.focus(minutes: $1.minutes).coins } }
    var focusMinutes: Int { focusData.sessions.filter { $0.status == "done" && !$0.isBreak }.reduce(0) { $0 + $1.minutes } }
    static let legacyGardenItems: [GardenItem] = [
        .init(id:"sprout",name:"Cây xanh",symbol:"leaf.fill",cost:0,category:"Cây"),
        .init(id:"cactus",name:"Xương rồng",symbol:"sun.max.fill",cost:80,category:"Cây"),
        .init(id:"sunflower",name:"Hướng dương",symbol:"sun.max.fill",cost:120,category:"Cây"),
        .init(id:"cherry",name:"Anh đào",symbol:"camera.macro",cost:180,category:"Cây"),
        .init(id:"pine",name:"Thông xanh",symbol:"tree.fill",cost:240,category:"Cây"),
        .init(id:"orange",name:"Cam ngọt",symbol:"circle.fill",cost:300,category:"Cây"),
        .init(id:"mushroom",name:"Nấm cổ tích",symbol:"sparkles",cost:380,category:"Cây"),
        .init(id:"bonsai",name:"Bonsai",symbol:"tree.fill",cost:500,category:"Cây"),
        .init(id:"potBlue",name:"Chậu men xanh",symbol:"cup.and.saucer.fill",cost:60,category:"Chậu"),
        .init(id:"potPink",name:"Chậu hồng",symbol:"cup.and.saucer.fill",cost:90,category:"Chậu"),
        .init(id:"potGold",name:"Chậu hoàng kim",symbol:"crown.fill",cost:250,category:"Chậu"),
        .init(id:"nightSky",name:"Đêm đầy sao",symbol:"moon.stars.fill",cost:120,category:"Nền"),
        .init(id:"sunset",name:"Hoàng hôn",symbol:"sun.haze.fill",cost:160,category:"Nền"),
        .init(id:"snow",name:"Vườn tuyết",symbol:"snowflake",cost:220,category:"Nền"),
        .init(id:"butterfly",name:"Bướm ghé thăm",symbol:"butterfly.fill",cost:100,category:"Trang trí"),
        .init(id:"lantern",name:"Đèn lồng",symbol:"lamp.desk.fill",cost:140,category:"Trang trí"),
        .init(id:"fence",name:"Hàng rào gỗ",symbol:"rectangle.split.3x1",cost:180,category:"Trang trí"),
        .init(id:"stars",name:"Bụi sao",symbol:"sparkles",cost:260,category:"Trang trí")
    ]
    static var gardenItems: [GardenItem] {
        legacyGardenItems.filter { $0.category != "Chậu" }.map { legacy in
            var item = legacy
            item.cost *= 3
            return item
        }
    }
    var currentGrowth: PlantGrowth { focusData.growth[focusData.selectedPlant] ?? PlantGrowth() }
    static let stages = ["Chồi non","Lá non","Cây nhỏ","Vươn cao","Tán xanh","Tỏa bóng","Sum suê","Trưởng thành"]
    static let maxPlantLevel = 100
    static let maxPlantPoints = 20000
    // 99 level-ups, with nondecreasing integer costs from 1 to 404 XP.
    // Derive the linear slope from the XP budget, then distribute rounding
    // to the final levels so level 100 starts at exactly 20,000 XP.
    static let plantLevelThresholds: [Int] = {
        let steps = maxPlantLevel - 1
        let span = 2 * maxPlantPoints / steps - 2
        var costs = (0..<steps).map { 1 + span * $0 / (steps - 1) }
        let remainder = maxPlantPoints - costs.reduce(0, +)
        for index in (steps - remainder)..<steps { costs[index] += 1 }
        var thresholds = [0]
        for cost in costs { thresholds.append(thresholds.last! + cost) }
        return thresholds
    }()
    // 100 levels across 8 stages: alternating groups of 13 and 12 levels.
    static let stageStartLevels = stages.indices.map { 1 + ($0 * maxPlantLevel + stages.count - 1) / stages.count }
    static let growthThresholds = stageStartLevels.map { plantLevelThresholds[$0 - 1] }
    func plantLevel(_ growth: PlantGrowth) -> Int {
        let points = max(0, growth.totalPoints)
        var lower = 0, upper = Self.plantLevelThresholds.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if Self.plantLevelThresholds[middle] <= points { lower = middle + 1 }
            else { upper = middle }
        }
        return max(1, min(Self.maxPlantLevel, lower))
    }
    func stage(_ growth: PlantGrowth) -> Int {
        (plantLevel(growth) - 1) * Self.stages.count / Self.maxPlantLevel
    }
    mutating func nourish(points: Int, plant: String? = nil) {
        var data = focusData
        let id = plant ?? data.selectedPlant
        var growth = data.growth[id] ?? PlantGrowth()
        growth.points = growth.totalPoints + points
        data.growth[id] = growth
        state.focus = data
    }
    mutating func startFocus(minutes: Int, strict: Bool = true, isBreak: Bool = false, now: Date) throws {
        guard focusData.active == nil, (isBreak ? (5...60).contains(minutes) && minutes % 5 == 0 : (10...180).contains(minutes)) else { throw GardenError.invalid(L("Đã có phiên đang chạy hoặc thời lượng không hợp lệ.", "A session is already running or the duration is invalid.")) }
        var data = focusData
        data.awaitingRest = false
        data.departure = nil
        if !isBreak { data.preferredMinutes = minutes }
        data.active = FocusSession(started:now, ends:now.addingTimeInterval(Double(minutes)*60),minutes:minutes,plantID:data.selectedPlant,strict:isBreak ? false : strict,isBreak:isBreak)
        state.focus = data
    }
    mutating func finishFocus(now: Date, cancel: Bool = false) throws {
        if !cancel && resolveFocusDeparture(now: now) { return }
        guard var session = focusData.active else { return }
        guard cancel || now >= session.ends else { return }
        session.status = cancel ? "cancelled" : "done"
        let earnedXP = !cancel && !session.isBreak ? TaskReward.focus(minutes: session.minutes).xp : 0
        session.earnedXP = earnedXP
        session.endedAt = cancel ? max(now, session.started) : session.ends
        session.completedSeconds = max(0, min(session.minutes * 60, Int(session.endedAt!.timeIntervalSince(session.started))))
        var data = focusData
        data.active = nil
        data.departure = nil
        data.sessions.append(session)
        data.awaitingRest = !cancel && !session.isBreak
        state.focus = data
        if !cancel && !session.isBreak {
            nourish(points:earnedXP,plant:session.plantID)
        }
    }
    @discardableResult
    mutating func interruptFocus(sessionID: UUID, departedAt: Date, endedAt: Date? = nil) -> Bool {
        guard var session = focusData.active, session.id == sessionID,
              session.strict, !session.isBreak, departedAt < session.ends else { return false }
        session.status = "interrupted"
        session.earnedXP = 0
        session.endedAt = max(endedAt ?? departedAt, session.started)
        session.completedSeconds = max(0, min(session.minutes * 60, Int(session.endedAt!.timeIntervalSince(session.started))))
        var data = focusData
        data.preferredMinutes = session.minutes
        data.active = nil
        data.awaitingRest = false
        data.sessions.append(session)
        state.focus = data
        return true
    }
    @discardableResult
    mutating func leaveFocus(at now: Date) -> Bool {
        guard let active = focusData.active, active.strict, !active.isBreak, now >= active.started, now < active.ends,
              focusData.departure == nil else { return false }
        var data = focusData
        data.departure = FocusDeparture(sessionID: active.id, date: now)
        state.focus = data
        return true
    }
    @discardableResult
    mutating func resolveFocusDeparture(now: Date) -> Bool {
        guard var departure = focusData.departure,
              departure.shouldInterrupt(focusData.active, now: now) else { return false }
        guard interruptFocus(sessionID: departure.sessionID, departedAt: departure.date, endedAt: departure.deadline) else { return false }
        departure.failedAt = departure.deadline
        var data = focusData
        data.departure = departure
        state.focus = data
        return true
    }
    // A lock signal can arrive after backgrounding or even after the deadline.
    // Undo only this unresolved departure, never an older/manual cancellation.
    @discardableResult
    mutating func recordFocusLock(at now: Date) -> Bool {
        guard var departure = focusData.departure, now >= departure.date else { return false }
        if let returned = departure.returnedAt, now.timeIntervalSince(returned) > 2 { return false }
        var data = focusData
        if departure.failedAt != nil {
            guard data.active == nil, var failed = data.sessions.last,
                  failed.id == departure.sessionID, failed.status == "interrupted" else { return false }
            data.sessions.removeLast()
            failed.status = "running"; failed.earnedXP = nil
            failed.endedAt = nil; failed.completedSeconds = nil
            data.active = failed
            data.awaitingRest = false
        }
        departure.lockedAt = now
        departure.failedAt = nil
        departure.noticeShown = false
        data.departure = departure
        state.focus = data
        return true
    }
    mutating func returnToFocus(at now: Date) {
        _ = resolveFocusDeparture(now: now)
        var data = focusData
        guard var departure = data.departure else { return }
        if departure.failedAt == nil { data.departure = nil }
        else { if departure.returnedAt == nil { departure.returnedAt = max(now, departure.date) }; data.departure = departure }
        state.focus = data
    }
    mutating func chooseItem(_ id: String) throws {
        guard let item = Self.gardenItems.first(where:{$0.id == id}) else { throw GardenError.invalid(L("Không tìm thấy vật phẩm.", "Item not found.")) }
        if item.cost > 0 && !owned.contains(id) {
            guard coins >= item.cost else { throw GardenError.invalid(L("Bạn chưa đủ xu.", "Not enough coins.")) }
            state.redemptions.append(Redemption(rewardID:id,title:item.name,cost:item.cost,date:Date()))
            pruneRewards()
        }
        var data = focusData
        if item.category == "Cây" { data.selectedPlant = id }
        else { data.decorations[item.category] = id }
        state.focus = data
    }
    func validateFocus() throws {
        let data = focusData
        let validIDs = Set(Self.gardenItems.filter{$0.category == "Cây"}.map(\.id))
        guard data.growthRevision == nil || (1...Self.plantProgressRevision).contains(data.growthRevision!),
              data.preferredMinutes == nil || (10...180).contains(data.preferredMinutes!),
              validIDs.contains(data.selectedPlant), data.selectedPlant == "sprout" || owned.contains(data.selectedPlant),
              Set(data.sessions.map(\.id)).count == data.sessions.count,
              data.awaitingRest != true || data.active == nil,
              data.sessions.count <= 100000 else { throw GardenError.invalid(L("Dữ liệu focus không hợp lệ.", "Invalid focus data.")) }
        guard fertilizerUses.count <= 100000,
              Set(fertilizerUses.map(\.id)).count == fertilizerUses.count,
              fertilizerUses.allSatisfy({ use in
                  validIDs.contains(use.plantID) && (use.plantID == "sprout" || owned.contains(use.plantID))
                      && use.productID == "fertilizer-25-v1" && (1...25).contains(use.xp) && use.cost == use.xp * 2
                      && (1...Self.plantProgressRevision).contains(use.growthRevision)
              }) else { throw GardenError.invalid(L("Lịch sử phân bón không hợp lệ.", "Invalid fertilizer history.")) }
        for session in data.sessions + (data.active.map{[$0]} ?? []) {
            guard (session.isBreak ? (5...60).contains(session.minutes) && session.minutes % 5 == 0 : (10...180).contains(session.minutes)),
                  validIDs.contains(session.plantID), ["running","done","cancelled","interrupted"].contains(session.status),
                  session.earnedXP == nil || session.earnedXP == (session.status == "done" && !session.isBreak ? session.minutes : 0),
                  session.status != "running" || session.earnedXP == nil,
                  session.completedSeconds == nil || (0...(session.minutes * 60)).contains(session.completedSeconds!),
                  session.endedAt == nil || session.endedAt! >= session.started,
                  session.status != "running" || (session.endedAt == nil && session.completedSeconds == nil),
                  abs(session.ends.timeIntervalSince(session.started) - Double(session.minutes)*60) < 1 else { throw GardenError.invalid(L("Phiên focus không hợp lệ.", "Invalid focus session.")) }
        }
        if let departure = data.departure {
            let session = data.active ?? data.sessions.last
            guard let session, session.id == departure.sessionID, session.strict, !session.isBreak,
                  departure.date >= session.started, departure.date < session.ends,
                  departure.lockedAt == nil || departure.lockedAt! >= departure.date,
                  departure.returnedAt == nil || departure.returnedAt! >= departure.date,
                  departure.lockedAt == nil || departure.failedAt == nil,
                  departure.failedAt == nil ? session.status == "running" : session.status == "interrupted",
                  departure.failedAt == nil || departure.failedAt == departure.deadline else {
                throw GardenError.invalid(L("Trạng thái rời Focus không hợp lệ.", "Invalid Focus departure state."))
            }
        }
        guard data.sessions.allSatisfy({$0.status != "running"}), data.active == nil || data.active?.status == "running",
              data.active == nil || !data.sessions.contains(where:{$0.id == data.active?.id}),
              data.growth.allSatisfy({validIDs.contains($0.key) && (0...1_000_000).contains($0.value.water) && (0...100_000_000).contains($0.value.sunlight) && ($0.value.points == nil || (0...1_000_000_000).contains($0.value.points!))}),
              data.decorations.allSatisfy({ pair in Self.legacyGardenItems.contains(where:{$0.id == pair.value && $0.category == pair.key}) && owned.contains(pair.value) }) else { throw GardenError.invalid(L("Khu vườn không hợp lệ.", "Invalid garden data.")) }
    }
}
