import Foundation

// Language is a device preference; it never rewrites saved user content or data keys.
enum AppLanguage {
    static var isEnglish: Bool { UserDefaults.standard.string(forKey: "appLanguage") == "en" }
    static var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "vi_VN") }
    static func date(_ value: Date, includeTime: Bool = false) -> String {
        if includeTime { return value.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(locale)) }
        return value.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }
    static func weekday(_ day: Int) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][max(0, min(6, day - 1))]
    }
    static func text(_ value: String) -> String { isEnglish ? (names[value] ?? value) : value }
    private static let names: [String: String] = [
        "Cây": "Plants",
        "Nền": "Background",
        "Trang trí": "Decorations",
        "Cây xanh": "Green sprout",
        "Xương rồng": "Cactus",
        "Hướng dương": "Sunflower",
        "Anh đào": "Cherry blossom",
        "Thông xanh": "Pine",
        "Cam ngọt": "Orange tree",
        "Nấm cổ tích": "Mushroom",
        "Đêm đầy sao": "Starry night",
        "Hoàng hôn": "Sunset",
        "Vườn tuyết": "Snow garden",
        "Bướm ghé thăm": "Butterflies",
        "Đèn lồng": "Lantern",
        "Hàng rào gỗ": "Wooden fence",
        "Bụi sao": "Stardust",
        "Chồi non": "Sprout",
        "Lá non": "First leaves",
        "Cây nhỏ": "Sapling",
        "Vươn cao": "Growing tall",
        "Tán xanh": "Leafy canopy",
        "Tỏa bóng": "Shady tree",
        "Sum suê": "Flourishing",
        "Trưởng thành": "Fully grown",
        "Chậu đất nung": "Terracotta pot",
        "Một chiếc chậu ấm áp cho Mầm": "A terracotta pot",
        "Vườn đom đóm": "Firefly garden",
        "Thắp sáng góc vườn buổi tối": "Light up the evening garden",
        "Vườn cầu vồng": "Rainbow garden",
        "Một khoảng trời đầy sắc màu": "A colorful sky",
        "Một ly yêu thích": "A favorite drink",
        "Dành thời gian thưởng thức thật chậm": "Take a break with a favorite drink",
        "Một tối xem phim": "Movie night",
        "Chọn bộ phim bạn đã để dành": "Watch a movie from your list",
        "Phần thưởng bạn tự dành cho mình": "Your personal reward",
    ]
}

func L(_ vietnamese: String, _ english: String) -> String {
    AppLanguage.isEnglish ? english : vietnamese
}
