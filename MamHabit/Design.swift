import SwiftUI

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}
enum Palette {
    static let background = Color(hex: 0xF4F5F0)
    static let ink = Color(hex: 0x203B31)
    static let muted = Color(hex: 0x64716A)
    static let green = Color(hex: 0x285F49)
    static let mint = Color(hex: 0xE3EEDC)
    static let orange = Color(hex: 0xA75527)
    static let border = Color(hex: 0xDFE4DB)
    static func tint(_ key: String) -> Color {
        switch key { case "blue": return Color(hex: 0x3F6E9A); case "purple": return Color(hex: 0x786090); case "orange": return orange; default: return green }
    }
}
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.border.opacity(0.65), lineWidth: 1)) }
}
struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.body, design: .rounded).weight(.bold)).padding(.horizontal, 20).frame(minHeight: 50).frame(maxWidth: .infinity).foregroundStyle(.white).background(Palette.green.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}
struct CoinPill: View {
    var value: Int
    var body: some View { Label("\(value)", systemImage: "circle.inset.filled").font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(Palette.orange).padding(.horizontal, 13).padding(.vertical, 9).background(Color(hex: 0xF8EAD1), in: Capsule()).accessibilityLabel(L("\(value) xu", "\(value) coins")) }
}
struct SectionTitle: View {
    var title: String
    var detail: String = ""
    var body: some View { HStack(alignment: .firstTextBaseline) { Text(title).font(.system(.title3, design: .rounded).weight(.bold)); Spacer(); if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(Palette.muted) } }.foregroundStyle(Palette.ink) }
}

// All botanical artwork is bundled, so the garden works fully offline.
struct BotanicalImage: View {
    let name: String
    private var image: Image {
        #if os(macOS)
        if let root = ProcessInfo.processInfo.environment["FOCUZ_ART_ROOT"] ?? Bundle.main.resourceURL?.appendingPathComponent("Artwork").path,
           let art = NSImage(contentsOfFile: "\(root)/\(name).imageset/art.png") ?? NSImage(contentsOfFile: "\(root)/\(name).imageset/art.jpg") { return Image(nsImage: art) }
        #endif
        return Image(name)
    }
    var body: some View { image.resizable().interpolation(.high).scaledToFit() }
}

struct BotanicalScene: View {
    var plant: String
    var stage: Int
    var backdrop = "day"
    var decoration: String? = nil
    var rainbow = false
    private let sizes: [CGFloat] = [0.20,0.27,0.43,0.51,0.62,0.70,0.78,0.84]
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let phase = min(7,max(0,stage))
            let treeHeight = h * sizes[phase]
            ZStack(alignment: .topLeading) {
                BotanicalImage(name: "garden-\(backdrop)")
                    .aspectRatio(1.5,contentMode:.fill)
                    .frame(width:w,height:h).clipped()
                if rainbow {
                    BotanicalImage(name:"deco-rainbow").frame(width:w*0.42,height:h*0.35)
                        .position(x:w*0.24,y:h*0.24)
                }
                BotanicalImage(name:"tree-\(plant)-\(phase/2)")
                    .frame(width:w*0.83,height:treeHeight,alignment:.bottom)
                    .brightness(backdrop == "nightSky" ? -0.16 : 0)
                    .position(x:w*0.53,y:h*0.89-treeHeight/2)
                if let decoration {
                    BotanicalImage(name:"deco-\(decoration)")
                        .frame(width:w * (decoration == "fence" ? 0.37 : 0.23),height:h*0.32,alignment:.bottom)
                        .position(x:w*0.20,y:h * (decoration == "butterfly" || decoration == "stars" ? 0.45 : 0.79))
                }
            }
        }.clipped().accessibilityHidden(true)
    }
}

struct FocuzGardenArt: View {
    @EnvironmentObject var store: GardenStore
    var body: some View {
        let data = store.engine.focusData
        let stage = store.engine.stage(store.engine.currentGrowth)
        let backdrop = data.decorations["Nền"] ?? (store.engine.state.equipped == "night" ? "nightSky" : "day")
        let plantName = HabitEngine.gardenItems.first { $0.id == data.selectedPlant }?.name ?? "Cây"
        BotanicalScene(plant:data.selectedPlant,stage:stage,backdrop:backdrop,decoration:data.decorations["Trang trí"],rainbow:store.engine.state.equipped == "rainbow")
            .frame(height:250).clipShape(RoundedRectangle(cornerRadius:24))
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(L("\(plantName), cấp cây \(store.engine.plantLevel(store.engine.currentGrowth)) trên \(HabitEngine.maxPlantLevel), giai đoạn \(stage+1) trên 8, \(HabitEngine.stages[stage]), trồng trên đồng cỏ", "\(AppLanguage.text(plantName)), plant level \(store.engine.plantLevel(store.engine.currentGrowth)) of \(HabitEngine.maxPlantLevel), stage \(stage+1) of 8, \(AppLanguage.text(HabitEngine.stages[stage]))"))
    }
}

struct GardenItemArtwork: View {
    let item: GardenItem
    var body: some View {
        if item.category == "Cây" { BotanicalImage(name:"tree-\(item.id)-3") }
        else if item.category == "Nền" { BotanicalImage(name:"garden-\(item.id)").clipShape(RoundedRectangle(cornerRadius:12)) }
        else { BotanicalImage(name:"deco-\(item.id)") }
    }
}

struct PlantLevelBar: View {
    @EnvironmentObject var store: GardenStore
    var body: some View {
        let growth = store.engine.currentGrowth
        let level = store.engine.plantLevel(growth)
        let floor = HabitEngine.plantLevelThresholds[level - 1]
        let next = level < HabitEngine.maxPlantLevel ? HabitEngine.plantLevelThresholds[level] : floor
        let points = growth.totalPoints.formatted(.number.locale(AppLanguage.locale))
        HStack(spacing: 10) {
            Text(L("Cấp \(level)", "Level \(level)"))
                .lineLimit(1).minimumScaleFactor(0.7)
            ProgressView(value: level == HabitEngine.maxPlantLevel ? 1 : Double(growth.totalPoints - floor),
                         total: level == HabitEngine.maxPlantLevel ? 1 : Double(next - floor))
                .progressViewStyle(.linear)
                .tint(Palette.green)
                .scaleEffect(x: 1, y: 0.5)
                .frame(minWidth: 24, maxWidth: .infinity).frame(height: 4)
                .layoutPriority(-1)
                .accessibilityLabel(L("Tiến độ lên cấp cây", "Plant level progress"))
            Text(L("\(points) EXP", "\(points) XP"))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .font(.caption.weight(.semibold)).foregroundStyle(Palette.ink)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
    }
}
