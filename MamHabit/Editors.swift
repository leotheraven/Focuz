import SwiftUI
import UniformTypeIdentifiers

struct HabitEditor: View {
    @EnvironmentObject var store: GardenStore
    @Environment(\.dismiss) private var dismiss
    var habit: Habit?
    @State private var title = ""
    @State private var symbol = "leaf.fill"
    @State private var color = "green"
    @State private var target = 1
    @State private var unit = L("lần", "times")
    @State private var weekdays = Set(1...7)
    @State private var reminderEnabled = false
    @State private var reminderTime = Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var saving = false
    @State private var error: String?
    @State private var archive = false
    @State private var deleting = false
    private let icons = ["leaf.fill", "drop.fill", "book.closed.fill", "figure.walk", "moon.fill", "pencil", "heart.fill", "brain.head.profile", "sun.max.fill", "music.note", "laptopcomputer", "cup.and.saucer.fill"]
    var body: some View {
        NavigationStack {
            Form {
                Section(L("Thói quen", "Habits")) { TextField(L("Tên thói quen", "Habit name"), text: $title); TextField(L("Đơn vị (lần, ly…)", "Unit (times, glasses…)"), text: $unit); Stepper(L("Mục tiêu: \(target) \(unit)", "Target: \(target) \(unit)"), value: $target, in: 1...20) }
                Section(L("Biểu tượng", "Icon")) { LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) { ForEach(icons, id: \.self) { icon in Button { symbol = icon } label: { Image(systemName: icon).frame(minWidth: 36, minHeight: 44).frame(maxWidth: .infinity).foregroundStyle(symbol == icon ? .white : Palette.green).background(symbol == icon ? Palette.green : Palette.mint, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain).accessibilityLabel(iconLabel(icon)).accessibilityAddTraits(symbol == icon ? [.isSelected] : []) } } }
                Section(L("Màu sắc", "Color")) { Picker(L("Màu", "Color"), selection: $color) { Text(L("Lá xanh", "Green")).tag("green"); Text(L("Xanh biển", "Blue")).tag("blue"); Text(L("Tím", "Purple")).tag("purple"); Text(L("Cam đất", "Orange")).tag("orange") }.pickerStyle(.segmented) }
                Section(L("Lặp lại vào", "Repeat on")) { ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in Toggle(day == 1 ? L("Chủ nhật", "Sunday") : L("Thứ \(day)", "\(AppLanguage.weekday(day))"), isOn: Binding(get: { weekdays.contains(day) }, set: { value in if value { weekdays.insert(day) } else { weekdays.remove(day) } })) } }
                Section {
                    Toggle(L("Nhắc thói quen", "Habit reminder"), isOn: $reminderEnabled)
                    if reminderEnabled { DatePicker(L("Giờ nhắc", "Reminder time"), selection: $reminderTime, displayedComponents: .hourAndMinute) }
                } footer: { Text(L("Thông báo có âm thanh vào các ngày đã chọn.", "Sound notification on the selected days.")) }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if let habit { Section {
                    Button(habit.archived ? L("Tiếp tục thói quen", "Resume habit") : L("Tạm dừng thói quen", "Pause habit"), systemImage: habit.archived ? "play.circle" : "pause.circle") {
                        if habit.archived { if store.change({ $0.pauseHabit(habit.id, paused: false) }) { dismiss() } }
                        else { archive = true }
                    }
                    Button(L("Xóa thói quen", "Delete habit"), systemImage: "trash", role: .destructive) { deleting = true }
                } }
            }.formStyle(.grouped).tint(Palette.green)
                .navigationTitle(habit == nil ? L("Thêm thói quen", "Add habit") : L("Sửa thói quen", "Edit habit"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("Hủy", "Cancel")) { dismiss() }.disabled(saving) }; ToolbarItem(placement: .confirmationAction) { Button(L("Lưu", "Save")) { Task { await save() } }.fontWeight(.bold).disabled(saving) } }
                .confirmationDialog(L("Tạm dừng thói quen này?", "Pause this habit?"), isPresented: $archive, titleVisibility: .visible) { Button(L("Tạm dừng", "Pause")) { if let habit, store.change({ $0.archive(habit.id) }) { dismiss() } }; Button(L("Hủy", "Cancel"), role: .cancel) { } }
                .confirmationDialog(L("Xóa thói quen này?", "Delete this habit?"), isPresented: $deleting, titleVisibility: .visible) {
                    Button(L("Xóa thói quen", "Delete habit"), role: .destructive) { if let habit, store.change({ $0.deleteHabit(habit.id) }) { dismiss() } }
                    Button(L("Hủy", "Cancel"), role: .cancel) {}
                } message: { Text(L("Thói quen sẽ bị xóa khỏi danh sách. Lịch sử, xu và XP đã nhận được giữ lại.", "The habit will be removed. Your history, earned coins and XP will be kept.")) }
        }.onAppear { if let habit { title = habit.title; symbol = habit.symbol; color = habit.color; target = habit.target; unit = habit.unit; weekdays = habit.weekdays; reminderEnabled = habit.reminder != nil
            if let reminder = habit.reminder { reminderTime = Calendar.current.date(bySettingHour: reminder.hour, minute: reminder.minute, second: 0, of: Date()) ?? Date() }
        } }.presentationDetents([.large])
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 650)
        #endif
    }
    private func save() async {
        saving = true
        defer { saving = false }
        var next = habit ?? Habit(title: "", symbol: "leaf.fill", color: "green", target: 1, unit: L("lần", "times"), created: store.engine.day(Date()))
        next.title = title.trimmingCharacters(in: .whitespacesAndNewlines); next.symbol = symbol; next.color = color; next.target = target; next.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines); next.weekdays = weekdays
        let parts = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        next.reminder = reminderEnabled ? HabitReminder(hour: parts.hour ?? 20, minute: parts.minute ?? 0) : nil
        if next.unit.isEmpty { next.unit = L("lần", "times") }
        do {
            var engine = store.engine; try engine.saveHabit(next)
            if next.reminder != nil, !next.archived {
                _ = await store.authorizeHabitReminders()
            }
            if store.change({ try $0.saveHabit(next) }) { dismiss() } else { error = store.message }
        } catch { self.error = error.localizedDescription }
    }
    private func iconLabel(_ icon: String) -> String { let names = [L("Lá cây", "Leaf"), L("Nước", "Water"), L("Sách", "Book"), L("Đi bộ", "Walking"), L("Ngủ", "Sleep"), L("Viết", "Writing"), L("Sức khỏe", "Health"), L("Học tập", "Study"), L("Buổi sáng", "Morning"), L("Âm nhạc", "Music"), L("Công việc", "Work"), L("Đồ uống", "Drink")]; return names[icons.firstIndex(of: icon) ?? 0] }
}

struct RewardEditor: View {
    @EnvironmentObject var store: GardenStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var cost = 100
    @State private var error: String?
    var body: some View {
        NavigationStack { Form {
            Section(L("Phần thưởng", "Reward")) { TextField(L("Ví dụ: Một buổi đi cà phê", "e.g. A coffee break"), text: $title); Stepper(L("Giá: \(cost) xu", "Cost: \(cost) coins"), value: $cost, in: 10...10000, step: 10) }
            Section { Text(L("Bạn tự dành phần thưởng ngoài đời sau khi đổi xu. Không có giao dịch thanh toán trong app.", "Personal rewards are redeemed with coins. You arrange the reward yourself; no payment is made in the app.")).font(.subheadline).foregroundStyle(Palette.muted) }
            if let error { Text(error).foregroundStyle(.red) }
        }.formStyle(.grouped).navigationTitle(L("Thêm phần thưởng", "Add reward")).toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(L("Hủy", "Cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Thêm", "Add")) {
                    if store.change({ try $0.addReward(title: title, cost: cost) }) { dismiss() }
                    else { error = store.message }
                }
            }
        }
        }.presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 440)
        #endif
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: GardenStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appLanguage") private var language = "vi"
    @State private var petName = ""
    @State private var reminderTime = Date()
    @State private var exporter = false
    @State private var importer = false
    @State private var importing: Data?
    @State private var restoreConfirm = false
    @State private var error: String?
    @State private var editing: Habit?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                Section(L("Ngôn ngữ", "Language")) { Picker(L("Ngôn ngữ", "Language"), selection: $language) { Text("Tiếng Việt").tag("vi"); Text("English").tag("en") }.pickerStyle(.segmented) }
                Section(L("Tên cây", "Plant name")) { TextField(L("Tên cây", "Plant name"), text: $petName); Button(L("Lưu tên", "Save name")) { let name = petName.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty, name.count <= 24 else { error = L("Tên cây cần từ 1–24 ký tự.", "Use 1–24 characters for the plant name."); return }; if store.change({ $0.state.petName = name }) { error = L("Đã lưu tên cây.", "Plant name saved.") } } }
                Section(L("Nhắc nhở hằng ngày", "Daily reminder")) {
                    DatePicker(L("Giờ nhắc", "Time"), selection: $reminderTime, displayedComponents: .hourAndMinute)
                    Button(store.engine.state.reminderEnabled ? L("Cập nhật giờ nhắc", "Update reminder") : L("Bật lời nhắc", "Enable reminder")) { Task { busy = true; await store.setReminder(enabled: true, time: reminderTime); error = store.message ?? L("Đã đặt lời nhắc.", "Reminder set."); busy = false } }.disabled(busy)
                    if store.engine.state.reminderEnabled { Button(L("Tắt nhắc nhở", "Turn off reminder")) { Task { await store.setReminder(enabled: false, time: reminderTime) } } }
                }
                Section(L("Thói quen đang hoạt động", "Active habits")) {
                    ForEach(store.engine.state.habits.filter { !$0.archived && $0.deleted != true }) { habit in Button(habit.title) { editing = habit } }
                }
                Section(L("Thói quen tạm dừng", "Paused habits")) {
                    let paused = store.engine.state.habits.filter { $0.archived && $0.deleted != true }
                    if paused.isEmpty { Text(L("Không có thói quen tạm dừng", "No paused habits")).foregroundStyle(Palette.muted) }
                    ForEach(paused) { habit in
                        HStack { Button(habit.title) { editing = habit }; Spacer(); Button(L("Tiếp tục", "Resume")) { store.change { $0.pauseHabit(habit.id, paused: false) } } }
                    }
                }
                Section {
                    Button(L("Xuất bản sao lưu", "Export backup"), systemImage: "square.and.arrow.up") { exporter = true }.disabled(store.storageBlocked)
                    Button(L("Khôi phục từ tệp", "Restore from file"), systemImage: "square.and.arrow.down") { importer = true }
                } header: { Text(L("Dữ liệu của bạn", "Your data")) } footer: { Text(L("Dữ liệu lưu trên thiết bị, không cần tài khoản. Hãy xuất bản sao lưu trước khi gỡ app hoặc đổi cách cài.", "Data is stored on this device. Export a backup before uninstalling or reinstalling.")) }
                Section(L("Cách nhận thưởng", "Rewards")) { Text(L("Thói quen: 10 xu.\nRương mỗi ngày: 25 xu.\nFocus hoàn tất: 1 phút = 1 XP cây + 1 coin (Point).\nPhân bón: 50 xu = 25 XP cho cây được chọn.\nMỗi cây có EXP riêng. Thanh xanh đầy sẽ tăng một cấp.\nĐủ xu là mua được cây mới, bắt đầu từ 0 EXP.\nFocus không tự hoàn thành thói quen.\nXu chỉ dùng trong app, không đổi thành tiền.", "Habit: 10 coins.\nDaily reward: 25 coins.\nCompleted Focus: 1 minute = 1 plant XP + 1 coin (Point).\nFertilizer: 50 coins = 25 XP for the selected plant.\nEach plant keeps its own XP. Fill the green bar to level up.\nBuy a new plant with coins; it starts at 0 XP.\nFocus does not complete habits automatically.\nCoins have no cash value.")).font(.subheadline) }
                if let error { Section { Text(error).font(.subheadline) } }
                Section { Text("Focuz · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.2")").font(.caption).foregroundStyle(Palette.muted) }
            }.formStyle(.grouped).tint(Palette.green).navigationTitle(L("Cài đặt", "Settings"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("Xong", "Done")) { dismiss() } } }
                .fileExporter(isPresented: $exporter, document: BackupDocument(state: store.engine.state), contentType: .json, defaultFilename: "Mam-backup-\(store.engine.day(Date()))") { result in if case .failure(let failure) = result { error = failure.localizedDescription } }
                .fileImporter(isPresented: $importer, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get()
                        let granted = url.startAccessingSecurityScopedResource()
                        defer { if granted { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 20_000_000 else { throw GardenError.invalid(L("Tệp sao lưu phải dưới 20 MB.", "Backups must be smaller than 20 MB.")) }
                        let data = try Data(contentsOf: url)
                        _ = try HabitEngine(state: JSONDecoder().decode(GardenState.self, from: data)).validated()
                        importing = data; restoreConfirm = true
                    } catch { self.error = error.localizedDescription }
                }
                .alert(L("Thay dữ liệu hiện tại?", "Replace current data?"), isPresented: $restoreConfirm) { Button(L("Khôi phục", "Restore"), role: .destructive) { if let importing { do { try store.restore(importing); petName = store.engine.state.petName; error = L("Đã khôi phục thành công.", "Backup restored.") } catch { self.error = error.localizedDescription } }; importing = nil }; Button(L("Hủy", "Cancel"), role: .cancel) { importing = nil } } message: { Text(L("Dữ liệu trong bản sao lưu sẽ thay thế tiến độ và số xu hiện có. Hãy xuất bản sao lưu hiện tại trước nếu cần giữ lại.", "This backup will replace your current progress and coins. Export a backup first if you want to keep them.")) }
                .sheet(item: $editing) { HabitEditor(habit: $0) }
        }.onAppear { petName = store.engine.state.petName; reminderTime = Calendar.current.date(bySettingHour: store.engine.state.reminderHour, minute: store.engine.state.reminderMinute, second: 0, of: Date()) ?? Date() }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 680)
        #endif
    }
}
