import Foundation

@main
struct EngineTests {
    static func main() throws {
        var count = 0
        func expect(_ value: @autoclosure () -> Bool, _ name: String) {
            guard value() else { fatalError("FAIL: \(name)") }
            count += 1
            print("PASS: \(name)")
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))!
        var engine = HabitEngine(calendar: cal)
        var habit = Habit(title: "Water", symbol: "drop.fill", color: "blue", target: 2, unit: "cups", created: engine.day(today))
        try engine.saveHabit(habit)
        expect(engine.coins == 0 && engine.totalPlantXP == 0, "new user has no fabricated points")
        expect(engine.habits(on: today).count == 1, "scheduled habit appears")
        let first = try engine.check(habit.id, at: today)
        expect(!first && engine.coins == 0, "partial target gives no reward")
        let second = try engine.check(habit.id, at: today)
        expect(second && engine.coins == 10 && engine.totalPlantXP == 0, "completion grants one reward")
        _ = try engine.check(habit.id, at: today)
        expect(engine.coins == 10 && engine.entry(habit, on: today)?.count == 2, "extra taps cannot exceed target or duplicate reward")
        engine.undo(habit.id, at: today)
        expect(!engine.completed(habit, on: today), "undo changes recorded progress")
        _ = try engine.check(habit.id, at: today)
        expect(engine.coins == 10 && engine.totalPlantXP == 0, "undo and redo cannot mint points")
        expect(engine.canClaimChest(on: today), "all habits unlock daily chest")
        try engine.claimChest(at: today)
        expect(engine.coins == 35 && engine.totalPlantXP == 0, "chest grants correct bonus")
        do { try engine.claimChest(at: today); fatalError("duplicate chest") } catch { count += 1 }
        expect(engine.coins == 35, "chest can only be claimed once")
        do { try engine.redeem("terracotta", at: today); fatalError("negative balance") } catch { count += 1 }
        expect(engine.coins == 35, "insufficient balance does not mutate wallet")
        try engine.addReward(title: "Break", cost: 20)
        let reward = engine.state.customRewards[0]
        try engine.redeem(reward.id, at: today)
        expect(engine.coins == 15 && engine.state.redemptions.count == 1, "custom reward deducts coins")
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        _ = try engine.check(habit.id, at: tomorrow); _ = try engine.check(habit.id, at: tomorrow)
        expect(engine.coins == 25 && engine.streak(habit, at: tomorrow) == 2, "next day earns a new reward and grows streak")
        let later = cal.date(byAdding: .day, value: 2, to: tomorrow)!
        expect(engine.streak(habit, at: later) == 0, "missed scheduled day resets streak")
        let pending = cal.date(byAdding: .day, value: 1, to: tomorrow)!
        expect(engine.streak(habit, at: pending) == 2, "unfinished today does not erase yesterday's streak")
        habit.target = 5
        try engine.saveHabit(habit)
        expect(engine.entry(habit, on: tomorrow)?.target == 2, "editing target preserves existing day snapshot")
        _ = try engine.check(habit.id, at: later)
        expect(engine.entry(habit, on: later)?.target == 5, "new target applies to new day")
        engine.archive(habit.id)
        expect(engine.habits(on: today).isEmpty && engine.coins == 25, "archiving preserves wallet and history")
        expect(!engine.canClaimChest(on: later), "empty day cannot earn a chest")
        let encoded = try JSONEncoder().encode(engine.state)
        let decoded = try HabitEngine(state: JSONDecoder().decode(GardenState.self, from: encoded), calendar: cal).validated()
        expect(decoded.coins == engine.coins && decoded.state.checkIns.count == engine.state.checkIns.count, "backup roundtrip preserves balances and progress")
        var invalid = decoded
        invalid.state.version = 99
        do { _ = try invalid.validated(); fatalError("future schema accepted") } catch { count += 1 }
        invalid = decoded; invalid.state.checkIns.append(invalid.state.checkIns[0])
        do { _ = try invalid.validated(); fatalError("duplicate history accepted") } catch { count += 1 }
        invalid = decoded; invalid.state.checkIns[0].day = "2026-02-30"
        do { _ = try invalid.validated(); fatalError("invalid date accepted") } catch { count += 1 }
        invalid = decoded; invalid.state.equipped = "night"
        do { _ = try invalid.validated(); fatalError("unowned decoration accepted") } catch { count += 1 }
        var weekend = HabitEngine(calendar: cal)
        let friday = cal.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 12))!
        let monday = cal.date(byAdding: .day, value: 3, to: friday)!
        let workHabit = Habit(title: "Work", symbol: "book", color: "green", target: 1, unit: "lần", weekdays: Set(2...6), created: weekend.day(friday))
        try weekend.saveHabit(workHabit)
        _ = try weekend.check(workHabit.id, at: friday)
        _ = try weekend.check(workHabit.id, at: monday)
        expect(weekend.streak(workHabit, at: monday) == 2, "weekend rest days do not break weekday streak")
        let saturday = cal.date(byAdding: .day, value: 1, to: friday)!
        do { _ = try weekend.check(workHabit.id, at: saturday); fatalError("rest day accepted") } catch { count += 1 }
        let nearMidnight = cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 23, minute: 59))!
        let afterMidnight = nearMidnight.addingTimeInterval(120)
        expect(weekend.day(nearMidnight) == "2026-11-12" && weekend.day(afterMidnight) == "2026-11-13", "day keys change at local midnight")
        var invalidHabit = habit; invalidHabit.weekdays = []
        do { try weekend.saveHabit(invalidHabit); fatalError("empty schedule accepted") } catch { count += 1 }
        do { try weekend.addReward(title: "", cost: 10); fatalError("empty reward accepted") } catch { count += 1 }
        // Enough earned days to buy a decoration, then equip it again without charging.
        for offset in 1...45 {
            let d = cal.date(byAdding: .day, value: offset, to: monday)!
            if weekend.scheduled(workHabit, on: d) { _ = try weekend.check(workHabit.id, at: d) }
        }
        let before = weekend.coins
        try weekend.redeem("terracotta", at: monday)
        expect(weekend.coins == before - 180 && weekend.state.equipped == "terracotta", "decoration purchase equips it")
        try weekend.redeem("terracotta", at: monday)
        expect(weekend.coins == before - 180, "owned decorations are not charged twice")
        _ = try weekend.validated()

        var focus = HabitEngine.initial(at: today)
        let reading = focus.state.habits[1]
        try focus.startFocus(minutes:25,strict:false,now:today)
        try focus.finishFocus(now:today.addingTimeInterval(1499))
        expect(focus.focusMinutes == 0 && focus.focusData.active != nil,"focus cannot finish early")
        // A legacy link must also be ignored when settling an upgraded session.
        focus.state.focus!.active!.habitID = reading.id
        try focus.finishFocus(now:today.addingTimeInterval(1500))
        expect(focus.focusMinutes == 25 && focus.coins == 25 && focus.totalPlantXP == 25,"focus awards the shared coin/XP currencies")
        expect(focus.state.checkIns.isEmpty,"focus never auto-checks even a legacy linked habit")
        expect(focus.currentGrowth.totalPoints == 25 && focus.stage(focus.currentGrowth) == 0,"focus alone grows the selected tree")
        try focus.finishFocus(now:today.addingTimeInterval(1600))
        expect(focus.coins == 25 && focus.currentGrowth.totalPoints == 25,"focus reward and growth settle exactly once")
        _ = try focus.check(reading.id,at:today)
        expect(focus.coins == 35 && focus.totalPlantXP == 25 && focus.currentGrowth.totalPoints == 25,"habit adds coins while existing Focus plant XP stays unchanged")
        focus.undo(reading.id,at:today)
        _ = try focus.check(reading.id,at:today)
        expect(focus.currentGrowth.totalPoints == 25,"undo/recheck cannot mint growth")
        try focus.startFocus(minutes:10,strict:true,now:today)
        try focus.finishFocus(now:today.addingTimeInterval(30),cancel:true)
        expect(focus.focusMinutes == 25 && focus.currentGrowth.totalPoints == 25,"cancelled focus earns nothing")
        try focus.startFocus(minutes:5,strict:false,isBreak:true,now:today)
        try focus.finishFocus(now:today.addingTimeInterval(300))
        expect(focus.focusMinutes == 25 && focus.coins == 35 && focus.currentGrowth.totalPoints == 25,"break earns no rewards or growth")
        let legacyData = try JSONEncoder().encode(HabitEngine.initial(at:today).state)
        let legacyJSON = try JSONSerialization.jsonObject(with:legacyData) as! [String:Any]
        var withoutFocus = legacyJSON; withoutFocus.removeValue(forKey:"focus")
        let migrated = try JSONDecoder().decode(GardenState.self,from:JSONSerialization.data(withJSONObject:withoutFocus))
        expect(migrated.focus == nil && migrated.habits.count == 3,"v1 backup remains readable")
        let oldGrowth = try JSONDecoder().decode(PlantGrowth.self,from:Data("{\"water\":7,\"sunlight\":175}".utf8))
        expect(oldGrowth.totalPoints == 490 && focus.stage(oldGrowth) == 1,"legacy growth keeps earned points and uses the slower growth curve")
        var legacy = focus
        legacy.state.focus!.growth["sprout"] = oldGrowth
        legacy.nourish(points:20)
        expect(legacy.currentGrowth.totalPoints == 510,"first post-upgrade reward adds once to legacy growth")
        let legacyRoundtrip = try JSONDecoder().decode(GardenState.self,from:JSONEncoder().encode(legacy.state))
        expect(HabitEngine(state:legacyRoundtrip).currentGrowth.totalPoints == 510,"growth migration is stable across saves")
        try focus.startFocus(minutes:50,strict:false,now:today)
        let saved = try JSONEncoder().encode(focus.state)
        focus = try HabitEngine(state:JSONDecoder().decode(GardenState.self,from:saved)).validated()
        try focus.finishFocus(now:today.addingTimeInterval(3000))
        expect(focus.focusMinutes == 75,"running focus resumes after persistence roundtrip")
        do { try focus.chooseItem("cactus"); expect(false, "old cactus price cannot buy the repriced plant") }
        catch { expect(focus.coins == 85 && focus.focusData.selectedPlant == "sprout", "old cactus price cannot buy the repriced plant") }
        try focus.startFocus(minutes:180,strict:false,now:today)
        try focus.finishFocus(now:today.addingTimeInterval(10800))
        let beforePlantPurchase = focus.coins
        try focus.chooseItem("cactus")
        expect(focus.focusData.selectedPlant == "cactus" && focus.coins == beforePlantPurchase - 240,"plant unlock charges the new price")
        try focus.chooseItem("cactus")
        expect(focus.coins == beforePlantPurchase - 240,"owned plant selection is free")
        expect(focus.currentGrowth.totalPoints == 0,"new species starts its own growth")
        try focus.startFocus(minutes:25,strict:false,now:today)
        try focus.chooseItem("sprout")
        let oldSproutPoints = focus.currentGrowth.totalPoints
        try focus.finishFocus(now:today.addingTimeInterval(1500))
        expect(focus.focusData.growth["cactus"]!.totalPoints == 25 && focus.currentGrowth.totalPoints == oldSproutPoints,"changing species during focus still rewards the starting tree")
        var habitsOnly = HabitEngine.initial(at:today)
        _ = try habitsOnly.check(habitsOnly.state.habits[1].id,at:today)
        expect(habitsOnly.currentGrowth.totalPoints == 0 && habitsOnly.stage(habitsOnly.currentGrowth) == 0,"habits alone never grow trees")
        for threshold in HabitEngine.growthThresholds.indices {
            expect(focus.stage(PlantGrowth(points:HabitEngine.growthThresholds[threshold])) == threshold,"growth stage threshold \(threshold)")
        }
        expect(HabitEngine.gardenItems.allSatisfy{$0.category != "Chậu"},"pots are removed from the collection")
        var invalidGrowth = focus; invalidGrowth.state.focus!.growth["sprout"] = PlantGrowth(points:-1)
        do { _ = try invalidGrowth.validated(); expect(false,"negative growth is rejected") } catch { expect(true,"negative growth is rejected") }
        _ = try focus.validated()
        var lifecycle = HabitEngine.initial(at: today)
        let removable = lifecycle.state.habits[1]
        _ = try lifecycle.check(removable.id, at: today)
        let earnedCoins = lifecycle.coins, earnedXP = lifecycle.totalPlantXP, earnedGrowth = lifecycle.currentGrowth.totalPoints
        lifecycle.pauseHabit(removable.id, paused: true)
        expect(!lifecycle.habits(on: today).contains(where: { $0.id == removable.id }), "paused habits leave the daily schedule")
        lifecycle.pauseHabit(removable.id, paused: false)
        expect(lifecycle.habits(on: today).contains(where: { $0.id == removable.id }), "paused habits can resume")
        let rewardedAgain = try lifecycle.check(removable.id, at: today)
        expect(!rewardedAgain, "resume cannot grant the same reward twice")
        lifecycle.deleteHabit(removable.id)
        expect(!lifecycle.habits(on: today).contains(where: { $0.id == removable.id }), "deleted habits leave the daily schedule")
        expect(lifecycle.coins == earnedCoins && lifecycle.totalPlantXP == earnedXP && lifecycle.currentGrowth.totalPoints == earnedGrowth, "delete preserves wallet, XP and plant growth")
        expect(lifecycle.entry(removable, on: today)?.complete == true, "delete preserves historical check-ins")
        lifecycle.pauseHabit(removable.id, paused: false)
        expect(lifecycle.state.habits.first(where: { $0.id == removable.id })?.archived == true, "deleted habits cannot be resumed")
        do { try lifecycle.saveHabit(removable); expect(false, "deleted habits cannot be re-saved") } catch { expect(true, "deleted habits cannot be re-saved") }
        let lifecycleBackup = try JSONEncoder().encode(lifecycle.state)
        let reopenedLifecycle = try HabitEngine(state: JSONDecoder().decode(GardenState.self, from: lifecycleBackup)).validated()
        expect(reopenedLifecycle.state.habits.first(where: { $0.id == removable.id })?.deleted == true && reopenedLifecycle.coins == earnedCoins, "deletion and earned balance survive backup restore")
        expect(migrated.habits.allSatisfy { $0.deleted == nil }, "old backups decode without a deleted flag")
        let previousLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        defer { if let previousLanguage { UserDefaults.standard.set(previousLanguage, forKey: "appLanguage") } else { UserDefaults.standard.removeObject(forKey: "appLanguage") } }
        UserDefaults.standard.set("en", forKey: "appLanguage")
        expect(L("Tạm dừng", "Pause") == "Pause" && AppLanguage.locale.identifier == "en_US", "English preference selects English strings and dates")
        expect(AppLanguage.text("Anh đào") == "Cherry blossom" && HabitEngine.gardenItems.first?.category == "Cây", "localization preserves persisted garden keys")
        UserDefaults.standard.set("vi", forKey: "appLanguage")
        expect(L("Tạm dừng", "Pause") == "Tạm dừng" && AppLanguage.text("Anh đào") == "Anh đào", "Vietnamese preference restores Vietnamese UI")
        // Habit reminder migration, validation and weekly lifecycle.
        var reminders = HabitEngine.initial(at: today)
        var timedHabit = reminders.state.habits[1]
        timedHabit.weekdays = [2, 4, 6]
        timedHabit.reminder = HabitReminder(hour: 8, minute: 30)
        try reminders.saveHabit(timedHabit)
        expect(reminders.habitReminderPlans.count == 3 && Set(reminders.habitReminderPlans.map(\.weekday)) == [2,4,6], "habit reminders repeat only on selected weekdays")
        expect(reminders.habitReminderPlans.allSatisfy { $0.hour == 8 && $0.minute == 30 && $0.title == timedHabit.title }, "habit reminders carry the configured time and title")
        let reminderIDs = Set(reminders.habitReminderPlans.map(\.id))
        reminders.pauseHabit(timedHabit.id, paused: true)
        expect(reminders.habitReminderPlans.isEmpty, "pausing a habit removes its notification plans")
        reminders.pauseHabit(timedHabit.id, paused: false)
        expect(Set(reminders.habitReminderPlans.map(\.id)) == reminderIDs, "resuming reinstates reminders with stable identifiers")
        let savedReminder = try HabitEngine(state: JSONDecoder().decode(GardenState.self, from: JSONEncoder().encode(reminders.state))).validated()
        expect(savedReminder.habitReminderPlans == reminders.habitReminderPlans, "reminder times survive backup roundtrip")
        var badReminder = timedHabit; badReminder.reminder = HabitReminder(hour: 24, minute: 0)
        do { try reminders.saveHabit(badReminder); expect(false, "invalid reminder rejected") } catch { expect(true, "invalid reminder rejected") }
        reminders.deleteHabit(timedHabit.id)
        expect(reminders.habitReminderPlans.isEmpty, "deleting a habit removes its notification plans")
        expect(migrated.habits.allSatisfy { $0.reminder == nil }, "old habits migrate with reminders off")
        var capacity = HabitEngine.initial(at: today)
        for index in 0..<8 {
            try capacity.saveHabit(Habit(title: "Habit \(index)", symbol: "leaf", color: "green", target: 1, unit: "times", created: capacity.day(today), reminder: HabitReminder(hour: index, minute: 0)))
        }
        let beforeCapacity = capacity.state.habits.count
        do { try capacity.saveHabit(Habit(title: "Too many", symbol: "leaf", color: "green", target: 1, unit: "times", created: capacity.day(today), reminder: HabitReminder(hour: 20, minute: 0))); expect(false, "notification limit rejected") }
        catch { expect(capacity.state.habits.count == beforeCapacity, "notification limit rejects save without dropping existing reminders") }

        var manualRest = HabitEngine.initial(at: today)
        try manualRest.startFocus(minutes: 10, now: today)
        expect(manualRest.focusData.active?.strict == true, "focus defaults to strict")
        try manualRest.finishFocus(now: today.addingTimeInterval(599))
        expect(manualRest.focusData.active != nil && manualRest.focusData.awaitingRest != true, "unfinished focus cannot offer rest or earn rewards")
        try manualRest.finishFocus(now: today.addingTimeInterval(600))
        expect(manualRest.focusData.active == nil && manualRest.focusData.awaitingRest == true, "completed focus waits for the user to start rest")
        let waiting = try HabitEngine(state: JSONDecoder().decode(GardenState.self, from: JSONEncoder().encode(manualRest.state))).validated()
        expect(waiting.focusData.awaitingRest == true && waiting.focusData.active == nil, "rest prompt survives restart without starting a timer")
        try manualRest.finishFocus(now: today.addingTimeInterval(3600))
        expect(manualRest.coins == 10 && manualRest.focusData.active == nil, "waiting hours cannot auto-start rest or duplicate rewards")
        try manualRest.startFocus(minutes: 10, isBreak: true, now: today.addingTimeInterval(3600))
        expect(manualRest.focusData.active?.isBreak == true && manualRest.focusData.active?.minutes == 10 && manualRest.focusData.active?.strict == false && manualRest.focusData.awaitingRest == false, "manual rest uses chosen duration and clears the prompt")
        try manualRest.finishFocus(now: today.addingTimeInterval(4200))
        expect(manualRest.coins == 10 && manualRest.focusData.awaitingRest == false && manualRest.focusData.active == nil, "rest ends without a reward or another rest prompt")
        try manualRest.startFocus(minutes: 60, isBreak: true, now: today)
        expect(manualRest.focusData.active?.minutes == 60, "rest can be increased up to 60 minutes")
        try manualRest.finishFocus(now: today, cancel: true)
        do { try manualRest.startFocus(minutes: 65, isBreak: true, now: today); expect(false, "invalid rest rejected") } catch { expect(true, "invalid rest rejected") }
        try manualRest.startFocus(minutes: 10, now: today)
        try manualRest.finishFocus(now: today, cancel: true)
        expect(manualRest.focusData.awaitingRest == false && manualRest.coins == 10, "cancelled focus neither earns rewards nor offers completed rest")
        expect(HabitEngine.growthThresholds == [0,328,1245,2904,5052,8059,11449,15787], "visual stages begin at the correct progressive point thresholds")
        for threshold in 1..<HabitEngine.growthThresholds.count {
            expect(focus.stage(PlantGrowth(points: HabitEngine.growthThresholds[threshold] - 1)) == threshold - 1, "growth does not level up before threshold \(threshold)")
        }
        expect(focus.plantLevel(PlantGrowth(points:19999)) == 99 && focus.plantLevel(PlantGrowth(points:20000)) == 100 && focus.plantLevel(PlantGrowth(points:50000)) == 100, "max plant level begins at exactly 20000 points")
        expect(HabitEngine.gardenItems.allSatisfy { current in
            let old = HabitEngine.legacyGardenItems.first { $0.id == current.id }!
            return current.cost == old.cost * 3
        }, "all purchasable garden items cost triple while the starting plant stays free")
        expect(HabitEngine.catalog.first(where: { $0.id == "night" })?.cost == 360 && HabitEngine.catalog.first(where: { $0.id == "rainbow" })?.cost == 600, "reward-shop decorations use higher prices too")
        var oldOwner = HabitEngine.initial(at:today)
        try oldOwner.startFocus(minutes:180, now:today)
        try oldOwner.finishFocus(now:today.addingTimeInterval(10800))
        oldOwner.state.redemptions.append(Redemption(rewardID:"cactus", title:"Xương rồng", cost:80, date:today))
        let oldBalance = oldOwner.coins
        try oldOwner.chooseItem("cactus")
        let oldOwnerBackup = try HabitEngine(state:JSONDecoder().decode(GardenState.self, from:JSONEncoder().encode(oldOwner.state))).validated()
        expect(oldOwnerBackup.coins == oldBalance && oldOwnerBackup.focusData.selectedPlant == "cactus" && oldOwnerBackup.state.redemptions.last?.cost == 80, "old purchases retain original cost, ownership and balance after repricing")
        expect(engine.state.customRewards[0].cost == 20, "user-defined reward prices stay unchanged")
        let plantThresholds = HabitEngine.plantLevelThresholds
        expect(plantThresholds.count == 100 && plantThresholds.first == 0 && plantThresholds.last == 20000, "exactly 100 plant levels span 0 through 20000 points")
        let levelCosts = zip(plantThresholds, plantThresholds.dropFirst()).map { $1 - $0 }
        expect(levelCosts.allSatisfy { $0 > 0 } && zip(levelCosts, levelCosts.dropFirst()).allSatisfy { $0 <= $1 }, "every plant level needs positive points and later levels never get cheaper")
        expect(levelCosts.first == 1 && levelCosts.last == 404 && levelCosts.reduce(0,+) == 20000, "early levels cost one point and the final level costs 404")
        expect((1...100).allSatisfy { level in focus.plantLevel(PlantGrowth(points:plantThresholds[level-1])) == level }, "every one of the 100 level thresholds maps back to its exact level")
        expect((2...100).allSatisfy { level in focus.plantLevel(PlantGrowth(points:plantThresholds[level-1]-1)) == level-1 }, "no plant level is granted one point before its threshold")
        expect((1...100).allSatisfy { level in focus.stage(PlantGrowth(points:plantThresholds[level-1])) == (level-1)*8/100 }, "all 100 plant levels map to one of eight visual stages")
        expect((0..<20000).allSatisfy { point in focus.plantLevel(PlantGrowth(points:point)) <= focus.plantLevel(PlantGrowth(points:point+1)) }, "plant levels never decrease as points rise")
        expect(focus.plantLevel(PlantGrowth(points:0)) == 1 && focus.plantLevel(PlantGrowth(points:1)) == 2 && focus.plantLevel(PlantGrowth(points:20)) == 4, "the early growth curve advances quickly per plant XP")
        expect(focus.plantLevel(PlantGrowth(points:4849)) == 50 && focus.plantLevel(PlantGrowth(points:11144)) == 75, "midgame and late-game require progressively more total points")
        expect(focus.stage(PlantGrowth(points:15787)) == 7 && focus.plantLevel(PlantGrowth(points:15787)) == 89, "entering visual stage eight is not the same as reaching max level")
        expect(focus.plantLevel(PlantGrowth(points:1000000000)) == 100 && focus.stage(PlantGrowth(points:1000000000)) == 7, "legacy points over the cap keep level and art within bounds")
        var plantLevelOnly = HabitEngine.initial(at:today)
        _ = try plantLevelOnly.check(plantLevelOnly.state.habits[1].id, at:today)
        expect(plantLevelOnly.plantLevel(plantLevelOnly.currentGrowth) == 1 && plantLevelOnly.coins == 10, "habit coin rewards leave a new plant at level one")
        let stageCounts = (0..<8).map { phase in (1...100).filter { focus.stage(PlantGrowth(points: plantThresholds[$0-1])) == phase }.count }
        expect(stageCounts == [13,12,13,12,13,12,13,12], "eight stages cover all 100 levels in balanced groups of 12 or 13")
        let oldPoints = legacyRoundtrip.focus!.growth["sprout"]!.totalPoints
        expect(oldPoints == 510 && HabitEngine(state:legacyRoundtrip).plantLevel(HabitEngine(state:legacyRoundtrip).currentGrowth) == focus.plantLevel(PlantGrowth(points:510)), "existing plant points derive the new level without converting or resetting saved points")
        var onePerMinute = HabitEngine.initial(at:today)
        try onePerMinute.startFocus(minutes:25, now:today)
        try onePerMinute.finishFocus(now:today.addingTimeInterval(1500))
        expect(onePerMinute.coins == 25 && onePerMinute.totalPlantXP == 25 && onePerMinute.currentGrowth.totalPoints == 25 && onePerMinute.plantLevel(onePerMinute.currentGrowth) == 4, "25 completed focus minutes award exactly 25 coins and 25 plant EXP")
        expect(onePerMinute.focusData.sessions.last?.earnedXP == 25 && onePerMinute.focusMinutes == 25, "focus saves its actual EXP award and counts minutes directly")
        try onePerMinute.finishFocus(now:today.addingTimeInterval(1501))
        expect(onePerMinute.totalPlantXP == 25 && onePerMinute.coins == 25 && onePerMinute.currentGrowth.totalPoints == 25, "new-rate focus still awards exactly once")
        let newRateReopened = try HabitEngine(state:JSONDecoder().decode(GardenState.self, from:JSONEncoder().encode(onePerMinute.state))).validated()
        expect(newRateReopened.totalPlantXP == 25 && newRateReopened.focusMinutes == 25 && newRateReopened.currentGrowth.totalPoints == 25, "new focus EXP rate survives backup roundtrip")
        var oldRateJSON = try JSONSerialization.jsonObject(with:JSONEncoder().encode(onePerMinute.state)) as! [String:Any]
        var oldFocusJSON = oldRateJSON["focus"] as! [String:Any]
        var oldSessionsJSON = oldFocusJSON["sessions"] as! [[String:Any]]
        oldSessionsJSON[0].removeValue(forKey:"earnedXP")
        oldFocusJSON["sessions"] = oldSessionsJSON
        var oldGrowthJSON = oldFocusJSON["growth"] as! [String:[String:Any]]
        oldGrowthJSON["sprout"]!["points"] = 50
        oldFocusJSON["growth"] = oldGrowthJSON
        oldRateJSON["focus"] = oldFocusJSON
        var mixedRates = try HabitEngine(state:JSONDecoder().decode(GardenState.self, from:JSONSerialization.data(withJSONObject:oldRateJSON))).validated()
        expect(mixedRates.coins == 25 && mixedRates.totalPlantXP == 50 && mixedRates.focusMinutes == 25 && mixedRates.currentGrowth.totalPoints == 50, "old backups retain previously earned double EXP and their real minutes")
        try mixedRates.startFocus(minutes:25, now:today)
        try mixedRates.finishFocus(now:today.addingTimeInterval(1500))
        expect(mixedRates.coins == 50 && mixedRates.totalPlantXP == 75 && mixedRates.currentGrowth.totalPoints == 75 && mixedRates.focusMinutes == 50, "legacy and new-rate sessions add their own awards without changing history")
        let mixedReopened = try HabitEngine(state:JSONDecoder().decode(GardenState.self, from:JSONEncoder().encode(mixedRates.state))).validated()
        expect(mixedReopened.totalPlantXP == 75 && mixedReopened.currentGrowth.totalPoints == 75 && mixedReopened.focusMinutes == 50, "mixed reward rates remain stable over repeated saves")
        var invalidAward = onePerMinute
        invalidAward.state.focus!.sessions[0].earnedXP = -1
        do { _ = try invalidAward.validated(); expect(false, "negative saved EXP rejected") } catch { expect(true, "negative saved EXP rejected") }
        invalidAward.state.focus!.sessions[0].earnedXP = 50
        do { _ = try invalidAward.validated(); expect(false, "incorrect saved EXP rejected") } catch { expect(true, "incorrect saved EXP rejected") }
        var legacyRunning = HabitEngine.initial(at:today)
        try legacyRunning.startFocus(minutes:25, now:today)
        legacyRunning = try HabitEngine(state:JSONDecoder().decode(GardenState.self, from:JSONEncoder().encode(legacyRunning.state))).validated()
        try legacyRunning.finishFocus(now:today.addingTimeInterval(1500))
        expect(legacyRunning.totalPlantXP == 25 && legacyRunning.currentGrowth.totalPoints == 25, "sessions completed after update use the new rate even if restored while running")
        var separatePlants = HabitEngine.initial(at: today)
        for duration in [180, 60] {
            try separatePlants.startFocus(minutes: duration, now: today)
            try separatePlants.finishFocus(now: today.addingTimeInterval(Double(duration * 60)))
        }
        separatePlants.nourish(points: 4760)
        try separatePlants.chooseItem("cactus")
        expect(separatePlants.coins == 0 && separatePlants.currentGrowth.totalPoints == 0, "exactly enough coins buys cactus with zero plant EXP and no account gate")
        try separatePlants.startFocus(minutes: 25, now: today)
        try separatePlants.finishFocus(now: today.addingTimeInterval(1500))
        try separatePlants.chooseItem("sprout")
        expect(separatePlants.currentGrowth.totalPoints == 5000, "switching back to Green Sprout restores its own 5000 EXP")
        try separatePlants.chooseItem("cactus")
        expect(separatePlants.currentGrowth.totalPoints == 25 && separatePlants.coins == 25, "cactus keeps its separate 25 EXP and switching never charges twice")
        var resetGarden = separatePlants
        resetGarden.state.focus!.growthRevision = nil
        try resetGarden.startFocus(minutes: 45, now: today)
        let oldCoins = resetGarden.coins, oldSessions = resetGarden.focusData.sessions.count
        let didReset = try resetGarden.migratePlantProgress()
        expect(didReset, "pre-2.11 garden is reset by the explicit progress migration")
        expect(resetGarden.focusData.growth.isEmpty && resetGarden.focusData.growthRevision == HabitEngine.plantProgressRevision, "migration starts all species at zero EXP")
        expect(resetGarden.coins == oldCoins && resetGarden.owned.contains("cactus") && resetGarden.focusData.selectedPlant == "cactus", "reset preserves wallet, purchases and selected species")
        expect(resetGarden.focusData.active == nil && resetGarden.focusData.sessions.count == oldSessions + 1 && resetGarden.focusData.sessions.last?.status == "cancelled", "old active session cannot backfill EXP after the reset")
        resetGarden.nourish(points: 25)
        let resetAgain = try resetGarden.migratePlantProgress()
        expect(!resetAgain, "the reset runs once and is independent of future app updates")
        expect(resetGarden.currentGrowth.totalPoints == 25, "repeating migration preserves all new plant EXP")
        var futureGarden = resetGarden; futureGarden.state.focus!.growthRevision = 99
        do { _ = try futureGarden.validated(); expect(false, "future progress schema rejected") } catch { expect(true, "future progress schema rejected") }
        var interruption = HabitEngine.initial(at: today)
        try interruption.startFocus(minutes: 45, now: today)
        let interruptedID = interruption.focusData.active!.id
        expect(interruption.interruptFocus(sessionID: interruptedID, departedAt: today.addingTimeInterval(10)), "strict focus can be interrupted before it ends")
        expect(interruption.focusData.active == nil && interruption.focusData.preferredMinutes == 45 && interruption.coins == 0 && interruption.currentGrowth.totalPoints == 0, "interruption resets the full selected duration without EXP or coins")
        expect(!interruption.interruptFocus(sessionID: interruptedID, departedAt: today.addingTimeInterval(20)), "an interrupted session cannot be interrupted or rewarded twice")
        _ = try interruption.validated()
        try interruption.startFocus(minutes: 5, isBreak: true, now: today)
        expect(!interruption.interruptFocus(sessionID: interruption.focusData.active!.id, departedAt: today), "rest is never interrupted by strict focus logic")
        func roundtrip(_ value: HabitEngine) throws -> HabitEngine {
            try HabitEngine(state: JSONDecoder().decode(GardenState.self, from: JSONEncoder().encode(value.state)), calendar: cal).validated()
        }
        var grace = HabitEngine.initial(at: today)
        try grace.startFocus(minutes: 25, now: today)
        let originalID = grace.focusData.active!.id
        expect(grace.leaveFocus(at: today.addingTimeInterval(20)), "departure is saved without ending Focus")
        expect(!grace.leaveFocus(at: today.addingTimeInterval(25)) && grace.focusData.departure?.date == today.addingTimeInterval(20), "duplicate background events cannot extend the grace deadline")
        grace = try roundtrip(grace)
        expect(grace.focusData.active?.id == originalID && grace.focusData.departure != nil, "pending departure survives backup/restart")
        expect(!grace.resolveFocusDeparture(now: today.addingTimeInterval(29.99)), "return is allowed until the full grace period expires")
        grace.returnToFocus(at: today.addingTimeInterval(29.99))
        expect(grace.focusData.active?.id == originalID && grace.focusData.departure == nil && grace.focusData.sessions.isEmpty, "quick return continues the original countdown")
        _ = grace.leaveFocus(at: today.addingTimeInterval(40))
        expect(grace.resolveFocusDeparture(now: today.addingTimeInterval(50)), "a genuine departure fails at its ten-second deadline")
        expect(grace.coins == 0 && grace.currentGrowth.totalPoints == 0 && grace.focusData.awaitingRest != true, "grace failure grants no EXP, coins or Rest")
        expect(grace.focusData.sessions.last?.endedAt == today.addingTimeInterval(50) && grace.focusData.sessions.last?.completedSeconds == 50, "failure saves actual deadline and elapsed seconds")
        grace = try roundtrip(grace)
        expect(grace.focusData.departure?.failedAt != nil && grace.focusData.sessions.last?.status == "interrupted", "failure metadata remains durable")
        expect(grace.recordFocusLock(at: today.addingTimeInterval(51)), "late lock evidence repairs the unresolved departure")
        expect(grace.focusData.active?.id == originalID && grace.focusData.sessions.isEmpty && grace.focusData.departure?.lockedAt != nil, "repair restores the same session and removes its false failure")
        grace = try roundtrip(grace)
        try grace.finishFocus(now: today.addingTimeInterval(1500))
        expect(grace.coins == 25 && grace.currentGrowth.totalPoints == 25 && grace.focusData.sessions.count == 1, "a repaired locked session earns its original award exactly once")
        try grace.finishFocus(now: today.addingTimeInterval(1600))
        expect(grace.coins == 25 && grace.focusData.departure == nil, "repeated completion cannot reward the repair twice")
        var killed = HabitEngine.initial(at: today)
        try killed.startFocus(minutes: 25, now: today)
        _ = killed.leaveFocus(at: today.addingTimeInterval(20))
        killed = try roundtrip(killed)
        try killed.finishFocus(now: today.addingTimeInterval(3000))
        expect(killed.coins == 0 && killed.focusData.sessions.last?.status == "interrupted", "absolute-date reconciliation prevents a terminated departure earning success later")
        killed.returnToFocus(at: today.addingTimeInterval(3001))
        killed.returnToFocus(at: today.addingTimeInterval(3003))
        expect(killed.focusData.departure?.returnedAt == today.addingTimeInterval(3001), "repeated activation cannot reopen the old lock-repair window")
        expect(!killed.recordFocusLock(at: today.addingTimeInterval(3004)), "an unrelated lock long after returning cannot revive an old failure")
        try killed.startFocus(minutes: 25, now: today.addingTimeInterval(3010))
        expect(!killed.recordFocusLock(at: today.addingTimeInterval(3011)), "a new session clears the old departure and cannot revive it")
        var unlockRace = HabitEngine.initial(at: today)
        try unlockRace.startFocus(minutes: 25, now: today)
        _ = unlockRace.leaveFocus(at: today.addingTimeInterval(10))
        unlockRace.returnToFocus(at: today.addingTimeInterval(30))
        expect(unlockRace.recordFocusLock(at: today.addingTimeInterval(30.1)), "unlock evidence queued just after becoming active can repair the false failure")
        unlockRace.returnToFocus(at: today.addingTimeInterval(30.2))
        expect(unlockRace.focusData.active != nil && unlockRace.focusData.departure == nil, "unlock repair resumes normally without a permanent lock flag")
        var finishInGrace = HabitEngine.initial(at: today)
        try finishInGrace.startFocus(minutes: 25, now: today)
        _ = finishInGrace.leaveFocus(at: today.addingTimeInterval(1499))
        try finishInGrace.finishFocus(now: today.addingTimeInterval(1500))
        expect(finishInGrace.coins == 25 && finishInGrace.focusData.departure == nil, "completion before grace expiry remains successful")
        var invalidDeparture = unlockRace
        invalidDeparture.state.focus!.departure = FocusDeparture(sessionID: UUID(), date: today)
        do { _ = try invalidDeparture.validated(); expect(false, "mismatched departure identity rejected") } catch { expect(true, "mismatched departure identity rejected") }
        var cancelledGrace = HabitEngine.initial(at: today)
        try cancelledGrace.startFocus(minutes: 25, now: today)
        _ = cancelledGrace.leaveFocus(at: today.addingTimeInterval(10))
        try cancelledGrace.finishFocus(now: today.addingTimeInterval(12), cancel: true)
        expect(cancelledGrace.focusData.departure == nil && !cancelledGrace.recordFocusLock(at: today.addingTimeInterval(13)), "manual cancellation cannot be undone by a later lock signal")
        var backwardsClock = HabitEngine.initial(at: today)
        try backwardsClock.startFocus(minutes: 25, now: today)
        expect(!backwardsClock.leaveFocus(at: today.addingTimeInterval(-100)), "a backwards wall clock cannot save an invalid departure before session start")
        try backwardsClock.finishFocus(now: today.addingTimeInterval(-100), cancel: true)
        _ = try backwardsClock.validated()
        expect(backwardsClock.focusData.sessions.last?.completedSeconds == 0, "clock rollback during cancellation preserves a readable save with zero elapsed seconds")
        func habitWallet(days: Int) throws -> HabitEngine {
            var wallet = HabitEngine.initial(at: today)
            let id = wallet.state.habits[1].id
            for offset in 0..<days {
                _ = try wallet.check(id, at: cal.date(byAdding: .day, value: offset, to: today)!)
            }
            return wallet
        }
        let tenHabits = try habitWallet(days: 10)
        expect(tenHabits.coins == 100 && tenHabits.totalPlantXP == 0 && tenHabits.plantLevel(tenHabits.currentGrowth) == 1,
               "ten completed habits earn 100 coins while the plant stays small at zero XP")
        var dailyCoins = HabitEngine.initial(at: today)
        for task in dailyCoins.state.habits {
            for _ in 0..<task.target { _ = try dailyCoins.check(task.id, at: today) }
        }
        try dailyCoins.claimChest(at: today)
        expect(dailyCoins.coins == 55 && dailyCoins.totalPlantXP == 0, "three habits and the daily chest grant only coins, never plant XP")
        var habitFund = try habitWallet(days: 5)
        let pack = habitFund.fertilizerQuote()!
        expect(pack.xp == 25 && pack.cost == 50 && pack.plantID == "sprout", "fertilizer quotes 50 coins for 25 XP on the selected plant")
        try habitFund.fertilize(pack, at: today)
        expect(habitFund.coins == 0 && habitFund.currentGrowth.totalPoints == 25 && habitFund.fertilizerUses.count == 1,
               "fertilizer spends earned habit coins and adds the quoted plant XP atomically")
        expect(habitFund.focusMinutes == 0 && habitFund.focusData.sessions.isEmpty && habitFund.owned.isEmpty,
               "fertilizer is a consumable and never fabricates Focus minutes or permanent ownership")
        do { try habitFund.fertilize(pack, at: today); expect(false, "insufficient fertilizer coins rejected") }
        catch { expect(habitFund.coins == 0 && habitFund.currentGrowth.totalPoints == 25 && habitFund.fertilizerUses.count == 1,
                       "insufficient fertilizer coins leave wallet, XP and history unchanged") }
        let fundedID = habitFund.state.habits[1].id
        for offset in 5..<10 { _ = try habitFund.check(fundedID, at: cal.date(byAdding: .day, value: offset, to: today)!) }
        expect(habitFund.coins == 50 && habitFund.currentGrowth.totalPoints == 25, "more habits refill only the wallet after fertilizing")
        try habitFund.fertilize(habitFund.fertilizerQuote()!, at: today)
        habitFund = try roundtrip(habitFund)
        expect(habitFund.coins == 0 && habitFund.currentGrowth.totalPoints == 50 && habitFund.fertilizerUses.count == 2,
               "fertilizer can be bought repeatedly and both purchases survive backup roundtrip")
        try habitFund.startFocus(minutes: 25, now: today)
        try habitFund.finishFocus(now: today.addingTimeInterval(1500))
        expect(habitFund.coins == 25 && habitFund.currentGrowth.totalPoints == 75,
               "25 minutes of Focus still grants 25 plant XP and 25 coins after using fertilizer")
        var speciesFood = try habitWallet(days: 31)
        speciesFood.nourish(points: 5000)
        try speciesFood.chooseItem("cactus")
        let cactusFood = speciesFood.fertilizerQuote()!
        try speciesFood.chooseItem("sprout")
        try speciesFood.fertilize(cactusFood, at: today)
        expect(speciesFood.currentGrowth.totalPoints == 5000 && speciesFood.focusData.growth["cactus"]?.totalPoints == 25 && speciesFood.coins == 20,
               "a captured fertilizer quote feeds only its cactus and preserves Green Sprout's 5000 XP")
        try speciesFood.chooseItem("cactus")
        expect(speciesFood.currentGrowth.totalPoints == 25 && speciesFood.coins == 20, "switching plants preserves fertilizer XP and never charges twice")
        var almostMax = try habitWallet(days: 5)
        almostMax.nourish(points: 19990)
        let smallPack = almostMax.fertilizerQuote()!
        expect(smallPack.xp == 10 && smallPack.cost == 20, "near max level fertilizer is reduced and charged proportionally")
        try almostMax.fertilize(smallPack, at: today)
        expect(almostMax.currentGrowth.totalPoints == 20000 && almostMax.coins == 30 && almostMax.fertilizerQuote() == nil,
               "fertilizer reaches the exact XP cap without wasting coins or allowing another purchase")
        do { try almostMax.fertilize(smallPack, at: today); expect(false, "max-level fertilizer rejected") }
        catch { expect(almostMax.coins == 30 && almostMax.fertilizerUses.count == 1, "a stale or max-level quote cannot spend coins again") }
        var changedQuote = try habitWallet(days: 5)
        changedQuote.nourish(points: 19990)
        let beforeGrowth = changedQuote.fertilizerQuote()!
        changedQuote.nourish(points: 1)
        do { try changedQuote.fertilize(beforeGrowth, at: today); expect(false, "changed fertilizer quote rejected") }
        catch { expect(changedQuote.coins == 50 && changedQuote.currentGrowth.totalPoints == 19991,
                       "a quote changed by new growth requires confirmation again without spending") }
        let forged = FertilizerQuote(plantID: "sprout", xp: 5000, cost: 0)
        do { try changedQuote.fertilize(forged, at: today); expect(false, "forged fertilizer quote rejected") }
        catch { expect(changedQuote.coins == 50 && changedQuote.fertilizerUses.isEmpty, "forged free fertilizer cannot mint plant XP") }
        expect(changedQuote.fertilizerQuote(for: "cactus") == nil, "fertilizer cannot target an unowned species")
        var resetEconomy = habitFund
        resetEconomy.state.focus!.growthRevision = 2
        let spentBalance = resetEconomy.coins
        let resetEconomyDidMigrate = try resetEconomy.migratePlantProgress()
        expect(resetEconomyDidMigrate && resetEconomy.totalPlantXP == 0 && resetEconomy.focusData.growthRevision == HabitEngine.plantProgressRevision,
               "the previous revision resets every plant XP once for the 100-level garden")
        expect(resetEconomy.coins == spentBalance && resetEconomy.fertilizerUses.count == 2,
               "XP reset preserves the wallet and never refunds or replays old fertilizer purchases")
        try resetEconomy.startFocus(minutes: 25, now: today)
        try resetEconomy.finishFocus(now: today.addingTimeInterval(1500))
        let resetEconomyAgain = try resetEconomy.migratePlantProgress()
        expect(!resetEconomyAgain && resetEconomy.currentGrowth.totalPoints == 25,
               "reopening after the new reset preserves new Focus XP without replaying history")
        var badFood = habitFund
        badFood.state.fertilizations!.append(badFood.state.fertilizations![0])
        do { _ = try badFood.validated(); expect(false, "duplicate fertilizer ledger rejected") }
        catch { expect(true, "duplicate fertilizer ledger rejected") }
        badFood = habitFund; badFood.state.fertilizations![0].cost = Int.max
        do { _ = try badFood.validated(); expect(false, "overflowing fertilizer cost rejected") }
        catch { expect(true, "overflowing fertilizer cost rejected before wallet arithmetic") }
        badFood = habitFund; badFood.state.fertilizations![0].xp = -1
        do { _ = try badFood.validated(); expect(false, "negative fertilizer XP rejected") }
        catch { expect(true, "negative fertilizer XP rejected") }
        var resetFailure = HabitEngine.initial(at: today)
        try resetFailure.startFocus(minutes: 25, now: today)
        _ = resetFailure.leaveFocus(at: today.addingTimeInterval(10))
        _ = resetFailure.resolveFocusDeparture(now: today.addingTimeInterval(21))
        resetFailure.state.focus!.growthRevision = 2
        let resetFailedDeparture = try resetFailure.migratePlantProgress()
        expect(resetFailedDeparture && resetFailure.focusData.departure == nil && resetFailure.totalPlantXP == 0,
               "new XP reset clears an old failed departure while retaining its historical session")
        expect(!resetFailure.recordFocusLock(at: today.addingTimeInterval(22)) && resetFailure.focusData.active == nil,
               "late unlock after the economy reset cannot revive a pre-update session or reintroduce XP")
        print("\n\(count) checks passed.")

    }
}
