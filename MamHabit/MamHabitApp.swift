import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct MamHabitApp: App {
    @AppStorage("appLanguage") private var language = "vi"
    @StateObject private var store = GardenStore()
    #if os(iOS)
    private let screenDetector = ScreenStateDetector.shared
    #endif
    @Environment(\.scenePhase) private var scenePhase
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
                .environment(\.locale, Locale(identifier: language == "en" ? "en_US" : "vi_VN"))
                .onChange(of: language) { _, _ in store.resume() }
                .onReceive(timer) { _ in store.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .inactive { store.prepareForBackground() }
                    if phase == .background { store.backgroundFocus() }
                    if phase == .active { store.resume() }
                }
                #if os(iOS)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in store.screenLocked() }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in store.screenUnlocked() }
                .onReceive(NotificationCenter.default.publisher(for: ScreenStateDetector.didLock)) { event in
                    store.screenLocked(now: event.userInfo?["date"] as? Date ?? Date())
                }
                #endif
                #if os(macOS)
                .frame(minWidth: 375, idealWidth: 430, maxWidth: 900, minHeight: 550, idealHeight: 860)
                .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
                #endif
        }
        #if os(macOS)
        .windowResizability(.contentSize)
        .defaultSize(width: 430, height: 860)
        #endif
    }
}
