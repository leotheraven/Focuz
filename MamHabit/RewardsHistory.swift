import SwiftUI

struct RewardsView: View {
    @EnvironmentObject var store: GardenStore
    @State private var add = false
    @State private var selected: Reward?
    @State private var confirm = false
    private var history: [Redemption] {
        let fertilizer = store.engine.fertilizerUses.map { use in
            let name = HabitEngine.gardenItems.first { $0.id == use.plantID }?.name ?? "Cây xanh"
            let title = L("Phân bón · \(name) (+\(use.xp) XP)", "Fertilizer · \(AppLanguage.text(name)) (+\(use.xp) XP)")
            return Redemption(id: use.id, rewardID: "fertilizer-use", title: title, cost: use.cost, date: use.date)
        }
        return (store.engine.state.redemptions + fertilizer).reversed().sorted { $0.date > $1.date }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { Text(L("Đổi quà", "Rewards")).font(.largeTitle.bold()) }.frame(maxWidth: .infinity, alignment: .leading)
        Card { HStack(spacing: 16) { Image(systemName: "circle.inset.filled").font(.system(size: 40)).foregroundStyle(Palette.orange); VStack(alignment: .leading, spacing: 3) { Text(L("\(store.engine.coins) xu", "\(store.engine.coins) coins")).font(.title.bold()); Text(L("Số dư hiện có", "Available balance")).font(.caption).foregroundStyle(Palette.muted) }; Spacer() } }
        FertilizerCard()
        SectionTitle(title: L("Trang trí khu vườn", "Garden decorations"))
        ForEach(store.engine.rewards.filter { $0.decoration && $0.id != "terracotta" }) { reward in rewardCard(reward) }
        HStack { SectionTitle(title: L("Quà cho chính mình", "Personal rewards")); Button { add = true } label: { Image(systemName: "plus").frame(width: 44, height: 44).background(Palette.mint, in: Circle()) }.buttonStyle(.plain).accessibilityLabel(L("Thêm phần thưởng tự đặt", "Add personal reward")) }
        Text(L("Đổi xu, rồi tự dành phần thưởng ngoài đời.", "Redeem coins, then arrange your own reward.")).font(.caption).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading)
        ForEach(store.engine.rewards.filter { !$0.decoration }) { reward in rewardCard(reward) }
        if !history.isEmpty {
            SectionTitle(title: L("Quà đã nhận", "Redeemed rewards"))
            Card { VStack(alignment: .leading, spacing: 16) { ForEach(history) { item in HStack { VStack(alignment: .leading, spacing: 4) { Text(store.engine.state.customRewards.contains(where: { $0.id == item.rewardID }) ? item.title : AppLanguage.text(item.title)).font(.subheadline.weight(.semibold)); Text(AppLanguage.date(item.date)).font(.caption).foregroundStyle(Palette.muted) }; Spacer(); Text(L("−\(item.cost) xu", "−\(item.cost) coins")).font(.caption.weight(.bold)).foregroundStyle(Palette.orange) } } } }
        }
        Color.clear.frame(height: 1)
            .sheet(isPresented: $add) { RewardEditor() }
            .alert(L("Đổi phần thưởng?", "Redeem reward?"), isPresented: $confirm, presenting: selected) { reward in
                Button(L("Đổi \(reward.cost) xu", "Redeem for \(reward.cost) coins")) {
                    if store.change({ try $0.redeem(reward.id, at: Date()) }) { store.message = reward.decoration ? L("Đã mở khóa \(reward.title)! Ghé Khu vườn để xem nhé.", "Unlocked \(AppLanguage.text(reward.title)).") : L("Đã đổi \(reward.title). Hãy dành món quà này cho mình nhé!", "Redeemed \(reward.custom ? reward.title : AppLanguage.text(reward.title)).") }
                }
                Button(L("Để sau", "Later"), role: .cancel) { }
            } message: { reward in Text(L("\(reward.title)\nSố dư sau khi đổi: \(store.engine.coins - reward.cost) xu.", "\(reward.custom ? reward.title : AppLanguage.text(reward.title))\nRemaining balance: \(store.engine.coins - reward.cost) coins.")) }
    }
    private func rewardCard(_ reward: Reward) -> some View {
        let owned = reward.decoration && store.engine.owned.contains(reward.id)
        let enough = store.engine.coins >= reward.cost
        return Card {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: reward.symbol).font(.system(size: 26)).foregroundStyle(reward.decoration ? Palette.green : Palette.orange).frame(width: 56, height: 56).background(reward.decoration ? Palette.mint : Color(hex: 0xF7EDD8), in: RoundedRectangle(cornerRadius: 18)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(reward.custom ? reward.title : AppLanguage.text(reward.title)).font(.headline)
                    Text(AppLanguage.text(reward.detail)).font(.caption).foregroundStyle(Palette.muted)
                    Button {
                        if owned { store.change { $0.state.equipped = reward.id }; store.message = L("Đã dùng \(reward.title).", "Applied \(AppLanguage.text(reward.title)).") }
                        else { selected = reward; confirm = true }
                    } label: {
                        Text(owned ? (store.engine.state.equipped == reward.id ? L("Đang dùng", "Selected") : L("Sử dụng", "Use")) : L("Đổi \(reward.cost) xu", "Redeem for \(reward.cost) coins"))
                            .font(.subheadline.weight(.bold)).padding(.horizontal, 18).frame(minHeight: 44).foregroundStyle(owned || enough ? .white : Palette.muted).background(owned || enough ? Palette.green : Palette.background, in: Capsule())
                    }.buttonStyle(.plain).disabled((!enough && !owned) || store.engine.state.equipped == reward.id)
                    if !enough && !owned { Text(L("Còn \(reward.cost - store.engine.coins) xu nữa", "\(reward.cost - store.engine.coins) more coins needed")).font(.caption).foregroundStyle(Palette.muted) }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct FertilizerCard: View {
    @EnvironmentObject var store: GardenStore
    @State private var pending: FertilizerQuote?
    @State private var confirm = false
    private func plantName(_ id: String) -> String {
        AppLanguage.text(HabitEngine.gardenItems.first { $0.id == id }?.name ?? "Cây xanh")
    }
    var body: some View {
        let quote = store.engine.fertilizerQuote()
        let enough = quote.map { store.engine.coins >= $0.cost } ?? false
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "bag.fill").font(.title2).foregroundStyle(Palette.green)
                        .frame(width: 44, height: 44).background(Palette.mint, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Phân bón", "Fertilizer")).font(.headline)
                        Text(quote.map { L("+\($0.xp) XP cho \(plantName($0.plantID))", "+\($0.xp) XP for \(plantName($0.plantID))") }
                             ?? L("Cây đã đạt cấp tối đa", "Plant is at max level"))
                            .font(.subheadline).foregroundStyle(Palette.muted)
                    }
                }
                Button {
                    pending = quote
                    confirm = true
                } label: {
                    Text(quote.map { L("Bón ngay · \($0.cost) xu", "Fertilize · \($0.cost) coins") }
                         ?? L("Đã đạt cấp tối đa", "Max level reached"))
                }.buttonStyle(PrimaryButton()).disabled(!enough || store.storageBlocked)
                    .opacity(enough && !store.storageBlocked ? 1 : 0.45)
                if let quote, !enough {
                    Text(L("Cần thêm \(quote.cost - store.engine.coins) xu", "\(quote.cost - store.engine.coins) more coins needed"))
                        .font(.caption).foregroundStyle(Palette.muted)
                }
            }
        }
        .alert(L("Mua và bón phân?", "Buy and apply fertilizer?"), isPresented: $confirm, presenting: pending) { quote in
            Button(L("Bón · \(quote.cost) xu", "Apply · \(quote.cost) coins")) { store.fertilize(quote); pending = nil }
            Button(L("Hủy", "Cancel"), role: .cancel) { pending = nil }
        } message: { quote in
            Text(L("\(plantName(quote.plantID)): +\(quote.xp) XP. Số dư còn \(store.engine.coins - quote.cost) xu. Phân được dùng ngay cho cây này.",
                   "\(plantName(quote.plantID)): +\(quote.xp) XP. Remaining balance: \(store.engine.coins - quote.cost) coins. Applied immediately to this plant."))
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var store: GardenStore
    var days: [Date] { (-27...0).compactMap { store.engine.calendar.date(byAdding: .day, value: $0, to: store.today) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { Text(L("Lịch sử", "History")).font(.largeTitle.bold()) }.frame(maxWidth: .infinity, alignment: .leading)
        Card {
            VStack(alignment: .leading, spacing: 20) {
                SectionTitle(title: L("28 ngày gần nhất", "Last 28 days"))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 10) {
                    ForEach(days, id: \.self) { day in
                        let count = store.engine.state.checkIns.filter { $0.day == store.engine.day(day) && $0.complete }.count
                        VStack(spacing: 5) {
                            Text(day.formatted(.dateTime.day())).font(.caption.weight(.bold)).frame(maxWidth: .infinity).frame(height: 36).foregroundStyle(count > 0 ? .white : Palette.muted).background(count > 0 ? Palette.green.opacity(count >= 3 ? 1 : 0.8) : Palette.background, in: RoundedRectangle(cornerRadius: 10))
                            Text(count > 0 ? "\(count)" : "·").font(.system(size: 10)).foregroundStyle(Palette.muted)
                        }.accessibilityElement(children: .ignore).accessibilityLabel(L("\(AppLanguage.date(day)): \(count) thói quen hoàn thành", "\(AppLanguage.date(day)): \(count) completed habits"))
                    }
                }
                Text(L("Số nhỏ dưới mỗi ô là số thói quen đã hoàn thành.", "Numbers show completed habits.")).font(.caption).foregroundStyle(Palette.muted)
            }
        }
        SectionTitle(title: L("Chuỗi hiện tại", "Current streaks"))
        if store.engine.state.habits.filter({ !$0.archived && $0.deleted != true }).isEmpty { Card { Text(L("Thêm thói quen ở màn hình Hôm nay.", "Add a habit on the Today screen.")).foregroundStyle(Palette.muted) } }
        ForEach(store.engine.state.habits.filter { !$0.archived && $0.deleted != true }) { habit in
            Card { HStack { Image(systemName: habit.symbol).foregroundStyle(Palette.tint(habit.color)).frame(width: 28); Text(habit.title).font(.subheadline.weight(.semibold)); Spacer(); Label("\(store.engine.streak(habit, at: store.today))", systemImage: "flame.fill").font(.headline).foregroundStyle(Palette.orange) } }
        }
        Text(L("Chuỗi tính theo các buổi đã lên lịch; ngày nghỉ không làm mất chuỗi. Thay đổi lịch áp dụng cho cách tính chuỗi hiện tại, còn lịch sử ghi nhận vẫn được giữ nguyên.", "Streaks count scheduled days. Rest days do not break a streak.")).font(.caption).foregroundStyle(Palette.muted)
        SectionTitle(title: L("Những lần gần đây", "Recent activity"))
        let entries = store.engine.recentActivity
        if entries.isEmpty { Card { VStack(alignment: .leading, spacing: 8) { Image(systemName: "sparkles").foregroundStyle(Palette.orange); Text(L("Chưa có hoạt động", "No activity yet")).font(.headline); Text(L("Thói quen đã hoàn thành sẽ xuất hiện ở đây.", "Completed habits will appear here.")).font(.subheadline).foregroundStyle(Palette.muted) } } }
        else { Card { VStack(spacing: 16) { ForEach(entries) { item in HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green); VStack(alignment: .leading, spacing: 4) { Text(item.title ?? "").font(.subheadline.weight(.semibold)); Text(store.engine.date(item.day).map { AppLanguage.date($0) } ?? item.day).font(.caption).foregroundStyle(Palette.muted) }; Spacer() } } } } }
    }
}
