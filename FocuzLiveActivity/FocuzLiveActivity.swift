import ActivityKit
import WidgetKit
import SwiftUI

@main
struct FocuzLiveActivityBundle: WidgetBundle {
    var body: some Widget { FocuzLiveActivityWidget() }
}

struct FocuzLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            HStack(spacing: 16) {
                Image(systemName: context.state.isBreak ? "cup.and.saucer.fill" : "leaf.fill")
                    .font(.title).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 5) {
                    Text(context.state.isBreak ? "Rest" : "Focuz · Strict").font(.headline)
                    Text(context.state.isBreak
                         ? (context.state.english ? "Rest ends" : "Kết thúc nghỉ")
                         : (context.state.english ? "Focus ends · tap to open" : "Kết thúc Focus · chạm để mở"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(context.state.ends, style: .time).font(.caption)
                }
                Spacer(minLength: 8)
                Text(timerInterval: context.state.started...context.state.ends, countsDown: true)
                    .font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
                    .multilineTextAlignment(.trailing).frame(width: 130)
            }.padding(18).foregroundStyle(Color(red: 0.12, green: 0.27, blue: 0.20)).activityBackgroundTint(Color(red: 0.96, green: 0.97, blue: 0.92))
                .activitySystemActionForegroundColor(.green)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.isBreak ? "Rest" : "Focuz · Strict",
                          systemImage: context.state.isBreak ? "cup.and.saucer.fill" : "leaf.fill")
                        .font(.headline).foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context).font(.title2).frame(width: 100)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(timerInterval: context.state.started...context.state.ends, countsDown: false)
                        .tint(.green).labelsHidden()
                }
            } compactLeading: {
                Image(systemName: context.state.isBreak ? "cup.and.saucer.fill" : "leaf.fill").foregroundStyle(.green)
            } compactTrailing: {
                countdown(context).frame(width: 60)
            } minimal: {
                Image(systemName: context.state.isBreak ? "cup.and.saucer.fill" : "timer").foregroundStyle(.green)
            }.keylineTint(.green)
        }
    }
    private func countdown(_ context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        Text(timerInterval: context.state.started...context.state.ends, countsDown: true).monospacedDigit()
    }
}
