import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: GardenStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appLanguage") private var language = "vi"
    @State private var tab = 0
    @State private var settings = false
    @State private var toastTask: Task<Void, Never>?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) { Image(systemName: "leaf.fill").font(.title3); Text("Focuz").font(.system(size: 28, weight: .heavy, design: .rounded)) }.foregroundStyle(Palette.green)
                Spacer()
                CoinPill(value: store.engine.coins).id(language)
                Button { settings = true } label: { Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel(L("Cài đặt và sao lưu", "Settings and backup"))
            }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 20) {
                    switch tab {
                    case 1: FocusScreen()
                    case 2: ExpandedGardenView()
                    case 3: RewardsView()
                    case 4: HistoryView()
                    default: HomeView()
                    }
                }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24).frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
            }.id("\(tab)-\(language)")
            HStack(spacing: 0) {
                tabButton(0, L("Hôm nay", "Today"), "house")
                tabButton(1, "Focus", "timer")
                tabButton(2, L("Vườn cây", "Garden"), "leaf")
                tabButton(3, L("Đổi quà", "Rewards"), "gift")
                tabButton(4, L("Lịch sử", "History"), "clock.arrow.circlepath")
            }.padding(.top, 10).padding(.bottom, 8).background(.white).overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
        }
        .font(.system(.body, design: .rounded)).foregroundStyle(Palette.ink)
        .background(Palette.background).preferredColorScheme(.light)
        .sheet(isPresented: $settings) { SettingsView() }
        .alert(L("Focus bị gián đoạn", "Focus interrupted"),
               isPresented: Binding(get: { store.interruptedSession != nil }, set: { if !$0 { store.dismissFocusInterruption() } }),
               presenting: store.interruptedSession) { _ in
            Button(L("Về Focus", "Go to Focus")) { store.dismissFocusInterruption(); tab = 1 }
            Button(L("Đóng", "Close"), role: .cancel) { store.dismissFocusInterruption() }
        } message: { session in
            Text(L("Bạn đã rời app quá 10 giây. Phiên này không nhận thưởng; đồng hồ đã về \(session.minutes) phút.", "You left the app for over 10 seconds. No rewards were earned; your timer is reset to \(session.minutes) minutes."))
        }
        .overlay(alignment: .top) {
            if let message = store.message {
                Button { store.message = nil } label: {
                    HStack(alignment: .top, spacing: 10) { Image(systemName: "sparkle"); Text(message).multilineTextAlignment(.leading); Image(systemName: "xmark").font(.caption) }
                        .font(.subheadline.weight(.semibold)).padding(18).foregroundStyle(.white).background(Palette.ink, in: RoundedRectangle(cornerRadius: 18)).shadow(color: .black.opacity(0.12), radius: 15, y: 4)
                }.buttonStyle(.plain).padding(20).accessibilityLabel(message + L(". Chạm để đóng.", ". Tap to dismiss."))
            }
        }
        .onChange(of: store.message) { _, value in
            toastTask?.cancel()
            if value != nil { toastTask = Task { try? await Task.sleep(for: .seconds(5)); if !Task.isCancelled { store.message = nil } } }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: store.message)
    }
    private func tabButton(_ value: Int, _ title: String, _ symbol: String) -> some View {
        Button { tab = value } label: {
            VStack(spacing: 5) { Image(systemName: symbol + (tab == value && [0, 2, 3].contains(value) ? ".fill" : "")).font(.system(size: 20, weight: .semibold)); Text(title).font(.caption.weight(tab == value ? .bold : .medium)) }
                .foregroundStyle(tab == value ? Palette.green : Palette.muted).frame(maxWidth: .infinity).frame(minHeight: 48)
        }.buttonStyle(.plain).accessibilityAddTraits(tab == value ? [.isSelected] : [])
    }
}

struct TodayView: View {
    @EnvironmentObject var store: GardenStore
    @State private var add = false
    @State private var editing: Habit?
    @State private var selected: Date?
    private var date: Date { selected ?? store.today }
    private var isToday: Bool { store.engine.day(date) == store.engine.day(store.today) }
    private var habits: [Habit] { store.engine.habits(on: date) }
    private var completeCount: Int { habits.filter { store.engine.completed($0, on: date) }.count }
    var body: some View {
        VStack(spacing: 18) {
            HStack { SectionTitle(title: isToday ? L("Thói quen hôm nay", "Today's habits") : L("Thói quen", "Habits"), detail: L("\(completeCount)/\(habits.count) xong", "\(completeCount)/\(habits.count) done")); Button { add = true } label: { Image(systemName: "plus").font(.headline).frame(width: 44, height: 44).background(Palette.mint, in: Circle()) }.buttonStyle(.plain).accessibilityLabel(L("Thêm thói quen", "Add habit")) }
            if habits.isEmpty {
                Card { VStack(alignment: .leading, spacing: 12) { Text(L("Chưa có thói quen", "No habits scheduled")).font(.headline); if isToday { Button(L("Thêm thói quen", "Add habit")) { add = true }.buttonStyle(PrimaryButton()) } } }
            }
            ForEach(habits) { habit in
                HabitRow(habit: habit, date: date, editable: isToday, onEdit: { editing = habit })
            }
            if isToday && !habits.isEmpty { chest }
            DisclosureGroup(L("7 ngày gần nhất", "Last 7 days")) { weekStrip }.font(.subheadline).tint(Palette.muted)
        }
        .sheet(isPresented: $add) { HabitEditor(habit: nil) }
        .sheet(item: $editing) { HabitEditor(habit: $0) }
    }
    private var weekStrip: some View {
        HStack(spacing: 4) {
            ForEach(-6...0, id: \.self) { offset in
                let day = store.engine.calendar.date(byAdding: .day, value: offset, to: store.today)!
                let active = store.engine.day(day) == store.engine.day(date)
                let count = store.engine.state.checkIns.filter { $0.day == store.engine.day(day) && $0.complete }.count
                Button { selected = offset == 0 ? nil : day } label: {
                    VStack(spacing: 8) { Text(day.formatted(.dateTime.weekday(.abbreviated).locale(AppLanguage.locale))).font(.system(size: 10, weight: .semibold)); Text(day.formatted(.dateTime.day())).font(.subheadline.weight(.bold)); Circle().fill(count > 0 ? (active ? Color.white : Palette.green) : Color.clear).frame(width: 4, height: 4) }.frame(maxWidth: .infinity).padding(.vertical, 10).foregroundStyle(active ? .white : Palette.muted).background(active ? Palette.green : .clear, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).accessibilityLabel(L("Ngày \(AppLanguage.date(day)), \(count) thói quen hoàn thành", "\(AppLanguage.date(day)), \(count) completed habits")).accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
    }
    private var chest: some View {
        let claimed = store.engine.state.chests.contains(store.engine.day(store.today))
        let ready = store.engine.canClaimChest(on: store.today)
        return Button {
            if ready && store.change({ try $0.claimChest(at: Date()) }) { store.message = L("+25 xu.", "+25 coins.") }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: claimed ? "checkmark.seal.fill" : "shippingbox.fill").font(.system(size: 28)).foregroundStyle(Palette.orange)
                VStack(alignment: .leading, spacing: 4) { Text(claimed ? L("Rương hôm nay đã mở", "Daily reward claimed") : L("Thưởng hôm nay", "Daily reward")).font(.headline); Text(claimed ? L("Đã nhận hôm nay", "Claimed for today") : ready ? L("Nhận 25 xu", "Claim 25 coins") : L("Xong tất cả để nhận 25 xu", "Complete all habits: 25 coins")).font(.caption).foregroundStyle(Palette.muted) }
                Spacer(minLength: 0)
                Image(systemName: claimed ? "checkmark" : ready ? "arrow.right" : "lock.fill").foregroundStyle(Palette.orange)
            }.padding(18).background(Color(hex: 0xF6EDD9), in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).disabled(!ready)
    }
}

struct HabitRow: View {
    @EnvironmentObject var store: GardenStore
    var habit: Habit
    var date: Date
    var editable: Bool
    var onEdit: () -> Void
    @State private var deleting = false
    private var entry: CheckIn? { store.engine.entry(habit, on: date) }
    private var done: Bool { entry?.complete ?? false }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: habit.symbol).font(.title3).foregroundStyle(Palette.tint(habit.color)).frame(width: 46, height: 46).background(Palette.tint(habit.color).opacity(0.1), in: RoundedRectangle(cornerRadius: 15)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(habit.title).font(.subheadline.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(done ? L("Hoàn thành", "Completed") : "\(entry?.count ?? 0)/\(entry?.target ?? habit.target) \(habit.unit)").foregroundStyle(Palette.muted)
                    if let reminder = habit.reminder { Label(reminder.label, systemImage: "bell").foregroundStyle(Palette.muted) }
                    let streak = store.engine.streak(habit, at: date)
                    if streak > 0 { Label("\(streak)", systemImage: "flame.fill").foregroundStyle(Palette.orange) }
                }.font(.caption)
            }
            Spacer(minLength: 0)
            if editable {
                Button { store.check(habit) } label: { Image(systemName: done ? "checkmark" : "plus").font(.headline).frame(width: 44, height: 44).foregroundStyle(done ? .white : Palette.green).background(done ? Palette.green : Palette.mint, in: Circle()) }.buttonStyle(.plain).disabled(done).accessibilityLabel(done ? L("\(habit.title), đã hoàn thành", "\(habit.title), completed") : L("Ghi nhận \(habit.title)", "Check in: \(habit.title)"))
                Menu {
                    Button(L("Chỉnh sửa", "Edit"), systemImage: "pencil", action: onEdit)
                    Button(L("Tạm dừng", "Pause"), systemImage: "pause.circle") { store.change { $0.archive(habit.id) } }
                    Button(L("Xóa thói quen", "Delete habit"), systemImage: "trash", role: .destructive) { deleting = true }
                    Button(L("Giảm một lần", "Undo one check-in"), systemImage: "arrow.uturn.backward") { store.change { $0.undo(habit.id, at: Date()) } }.disabled((entry?.count ?? 0) == 0)
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel(L("Tùy chọn \(habit.title)", "Options for \(habit.title)"))
            } else { Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? Palette.green : Palette.muted).font(.title2) }
        }.confirmationDialog(L("Xóa thói quen này?", "Delete this habit?"), isPresented: $deleting, titleVisibility: .visible) {
            Button(L("Xóa thói quen", "Delete habit"), role: .destructive) { store.change { $0.deleteHabit(habit.id) } }
            Button(L("Hủy", "Cancel"), role: .cancel) {}
        } message: { Text(L("Thói quen sẽ bị xóa khỏi danh sách. Lịch sử, xu và XP đã nhận được giữ lại.", "The habit will be removed. Your history, earned coins and XP will be kept.")) }
        .padding(14).background(done ? Color(hex: 0xF0F4EB) : .white, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.border.opacity(0.7), lineWidth: 1))
    }
}

struct HomeView: View {
    @EnvironmentObject var store: GardenStore
    @Environment(\.dynamicTypeSize) private var typeSize
    private var habits: [Habit] { store.engine.habits(on: store.today) }
    private var todayMinutes: Int {
        store.engine.focusData.sessions.filter { $0.status == "done" && !$0.isBreak && store.engine.day($0.ends) == store.engine.day(store.today) }.reduce(0) { $0 + $1.minutes }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.today.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.locale)))
                .font(.subheadline).foregroundStyle(Palette.muted)
            Text(L("Hôm nay", "Today")).font(.largeTitle.bold())
        }.frame(maxWidth: .infinity, alignment: .leading)
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            metric(L("Tập trung", "Focus"), value: "\(todayMinutes)", unit: L("phút", "min"), icon: "timer")
            if !typeSize.isAccessibilitySize { Divider().frame(height: 32) }
            metric(L("Thói quen", "Habits"), value: "\(habits.filter { store.engine.completed($0, on: store.today) }.count)/\(habits.count)", unit: L("xong", "done"), icon: "checkmark.circle")
        }.padding(.vertical, 14).background(.white, in: RoundedRectangle(cornerRadius: 20))
        TodayView()
    }
    private func metric(_ title: String, value: String, unit: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) { Text(value).font(.title3.bold()); Text(unit).font(.caption).foregroundStyle(Palette.muted) }
        }.frame(maxWidth: .infinity)
    }
}

struct FocusScreen: View {
    var body: some View {
        Text("Focus").font(.largeTitle.bold()).frame(maxWidth: .infinity, alignment: .leading)
        FocusView()
        FocuzGardenArt()
    }
}

struct FocusView: View {
    @EnvironmentObject var store: GardenStore
    private var minutes: Int { store.engine.focusData.preferredMinutes ?? 25 }
    private func setMinutes(_ value: Int) {
        store.change { engine in var data = engine.focusData; data.preferredMinutes = value; engine.state.focus = data }
    }
    @State private var restMinutes = 5
    @State private var starting = false
    @State private var cancel = false
    @State private var options = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(store.engine.focusData.active?.isBreak == true || store.engine.focusData.awaitingRest == true ? "Rest" : "Focus", systemImage: "timer").font(.headline)
                    Spacer()
                    if store.engine.focusData.active == nil && store.engine.focusData.awaitingRest != true {
                        Button { options = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44).background(Palette.background, in: Circle()) }
                            .buttonStyle(.plain).accessibilityLabel(L("Tùy chọn phiên", "Session options"))
                    }
                }
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let active = store.engine.focusData.active {
                            let seconds = max(0, min(active.minutes * 60, Int(ceil(active.ends.timeIntervalSince(store.today)))))
                            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).font(.system(size: 52, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                            Text(active.isBreak ? L("Đang nghỉ", "On break") : L("Đang tập trung", "Focusing")).font(.subheadline).foregroundStyle(Palette.muted)
                        } else {
                            Text(String(format: "%02d:00", store.engine.focusData.awaitingRest == true ? restMinutes : minutes)).font(.system(size: 52, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                            if store.engine.focusData.awaitingRest == true {
                                HStack(spacing: 4) {
                                    durationButton("minus", label: L("Giảm 5 phút nghỉ", "Decrease rest by 5 minutes"), disabled: restMinutes <= 5) { restMinutes = max(5, restMinutes - 5) }
                                    Text(L("phút", "min")).font(.caption).foregroundStyle(Palette.muted)
                                    durationButton("plus", label: L("Tăng 5 phút nghỉ", "Increase rest by 5 minutes"), disabled: restMinutes >= 60) { restMinutes = min(60, restMinutes + 5) }
                                }

                            } else { HStack(spacing: 4) {
                                durationButton("minus", label: L("Giảm 5 phút", "Decrease by 5 minutes"), disabled: minutes <= 10) { setMinutes(max(10, minutes - 5)) }
                                Text(L("phút", "min")).font(.caption).foregroundStyle(Palette.muted)
                                    .accessibilityLabel(L("Thời lượng: \(minutes) phút", "Duration: \(minutes) minutes"))
                                durationButton("plus", label: L("Tăng 5 phút", "Increase by 5 minutes"), disabled: minutes >= 180) { setMinutes(min(180, minutes + 5)) }
                            }
                            }
                            Text(store.engine.focusData.awaitingRest == true ? L("Focus hoàn tất. Bắt đầu nghỉ khi sẵn sàng.", "Focus complete. Start your rest when ready.") : L("Strict · hoàn thành để nhận thưởng", "Strict · finish to earn rewards")).font(.caption).foregroundStyle(Palette.muted)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if !typeSize.isAccessibilitySize {
                        let data = store.engine.focusData
                        BotanicalScene(plant: data.selectedPlant, stage: store.engine.stage(store.engine.currentGrowth), backdrop: data.decorations["Nền"] ?? "day", decoration: data.decorations["Trang trí"])
                            .frame(width: 128, height: 120).clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                }
                if let active = store.engine.focusData.active {
                    let seconds = max(0, active.ends.timeIntervalSince(store.today))
                    ProgressView(value: max(0, Double(active.minutes * 60) - seconds), total: Double(active.minutes * 60)).tint(Palette.green)
                    if active.strict { Text(L("Strict · rời app sẽ reset phiên", "Strict · leaving resets the session")).font(.caption).foregroundStyle(Palette.orange) }
                    Button(L("Dừng phiên", "End session"), role: .destructive) { cancel = true }.frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.bordered)
                } else {
                    HStack(spacing: 12) {
                        Button {
                            starting = true
                            Task { await store.beginFocus(minutes: store.engine.focusData.awaitingRest == true ? restMinutes : minutes, isBreak: store.engine.focusData.awaitingRest == true); starting = false }
                        } label: { Label(starting ? L("Đang bắt đầu…", "Starting…") : (store.engine.focusData.awaitingRest == true ? L("Bắt đầu Rest", "Start rest") : L("Bắt đầu", "Start focus")), systemImage: "play.fill") }.buttonStyle(PrimaryButton()).disabled(starting)
                        if store.engine.focusData.awaitingRest == true {
                            Button(L("Bỏ qua", "Skip")) { store.skipRest() }
                                .buttonStyle(.plain).font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.muted)
                                .padding(.horizontal, 16).frame(minHeight: 50)
                                .background(Palette.background, in: RoundedRectangle(cornerRadius: 16))
                                .fixedSize(horizontal: true, vertical: false).disabled(starting)
                                .accessibilityLabel(L("Bỏ qua Rest", "Skip rest"))
                        }
                    }
                }
            }
        }.sheet(isPresented: $options) {
            NavigationStack {
                Form {
                    Section {
                        Label(L("Strict luôn bật", "Strict is always on"), systemImage: "lock.fill")
                    } footer: { Text(L("Không tạm dừng. Rời app: nhắc sau 5 giây, gián đoạn sau 10 giây. Quay lại kịp thì phiên tiếp tục. Khóa màn hình được phép; tín hiệu khóa/mở khóa đến muộn được đối soát để giữ phiên.", "No pausing. Leaving: reminder after 5 seconds, interruption after 10 seconds. Return in time to keep your session. Screen locks are allowed; delayed lock/unlock signals are reconciled to preserve the session.")) }
                    Section {
                        Button(L("Bật thông báo kết thúc phiên", "Enable session notifications")) { Task { await store.enableFocusNotifications() } }
                        Button(L("Rest 5 phút", "5-minute rest")) { options = false; Task { await store.beginFocus(minutes: 5, isBreak: true) } }
                        Button(L("Rest 10 phút", "10-minute rest")) { options = false; Task { await store.beginFocus(minutes: 10, isBreak: true) } }
                    }
                }.formStyle(.grouped).tint(Palette.green)
                    .navigationTitle(L("Tùy chọn phiên", "Session options"))
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Xong", "Done")) { options = false } } }
            }.presentationDetents([.medium, .large])
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 450)
            #endif
        }.onChange(of: store.engine.focusData.awaitingRest) { _, waiting in if waiting == true { restMinutes = 5 } }
        .confirmationDialog(store.engine.focusData.active?.isBreak == true ? L("Dừng Rest?", "End rest?") : L("Dừng phiên và bỏ phần thưởng?", "End session without rewards?"), isPresented: $cancel, titleVisibility: .visible) {
            Button(L("Dừng phiên", "End session"), role: .destructive) { store.cancelFocus() }
            Button(L("Tiếp tục", "Resume"), role: .cancel) {}
        }
    }
    private func durationButton(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(disabled ? Palette.muted : Palette.green)
                .background(disabled ? Palette.background : Palette.mint, in: Circle())
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.5 : 1)
            .accessibilityLabel(label)
    }
}
struct ExpandedGardenView: View {
    @EnvironmentObject var store: GardenStore
    @State private var category = "Cây"
    @State private var purchase: GardenItem?
    @State private var confirm = false
    var body: some View {
        SectionTitle(title:L("Vườn cây", "Garden"))
        FocuzGardenArt()
            .overlay(alignment: .top) { PlantLevelBar().frame(maxWidth: 260).padding(12) }
        FertilizerCard()
        ScrollView(.horizontal,showsIndicators:false) { HStack { ForEach(["Cây","Nền","Trang trí"],id:\.self) { item in Button(AppLanguage.text(item)) { category=item }.buttonStyle(.bordered).tint(category == item ? Palette.green : Palette.muted) } } }
        if category != "Cây" {
            Button(L("Dùng \(category.lowercased()) mặc định", "Reset \(AppLanguage.text(category).lowercased())")) { store.change { engine in var data=engine.focusData;data.decorations.removeValue(forKey:category);engine.state.focus=data } }.frame(minHeight:44)
        }
        ForEach(HabitEngine.gardenItems.filter{$0.category == category}) { item in
            let owned = item.cost == 0 || store.engine.owned.contains(item.id)
            let selected = item.category == "Cây" ? store.engine.focusData.selectedPlant == item.id : store.engine.focusData.decorations[item.category] == item.id
            Card {
                HStack(spacing:16) {
                    GardenItemArtwork(item: item).frame(width:86,height:86).accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:8) {
                        Text(AppLanguage.text(item.name)).font(.headline)
                        if item.category == "Cây" {
                            let growth = store.engine.focusData.growth[item.id] ?? PlantGrowth()
                            Text(L("Cấp \(store.engine.plantLevel(growth)) · \(growth.totalPoints) EXP", "Level \(store.engine.plantLevel(growth)) · \(growth.totalPoints) XP")).font(.caption).foregroundStyle(Palette.muted)
                        }
                        Text(owned ? L("Đã sở hữu", "Owned") : L("\(item.cost) xu", "\(item.cost) coins")).font(.caption)
                        Button(selected ? L("Đang dùng", "Selected") : owned ? L("Sử dụng", "Use") : L("Mở khóa", "Unlock")) {
                            if owned { store.change { try $0.chooseItem(item.id) } }
                            else { purchase=item;confirm=true }
                        }.buttonStyle(.borderedProminent).tint(Palette.green).disabled(selected || (!owned && store.engine.coins < item.cost))
                    }
                    Spacer(minLength:0)
                }
            }
        }
        Color.clear.frame(height:1).alert(L("Mở khóa món đồ?", "Unlock item?"),isPresented:$confirm,presenting:purchase) { item in
            Button(L("Đổi \(item.cost) xu", "Redeem for \(item.cost) coins")) { store.change { try $0.chooseItem(item.id) } }
            Button(L("Hủy", "Cancel"),role:.cancel) {}
        } message: { item in Text(L("\(item.name) sẽ được giữ vĩnh viễn trong bộ sưu tập của bạn.", "\(AppLanguage.text(item.name)) will stay in your collection.")) }
    }
}
