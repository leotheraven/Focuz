package com.mamhabit.personal;

import static com.mamhabit.personal.FocuzStore.*;

import android.Manifest;
import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.media.AudioAttributes;
import android.net.Uri;
import android.os.Build;
import android.util.Log;

import org.json.JSONObject;

import java.io.IOException;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;

public final class Alerts extends BroadcastReceiver {
    private static final String PREFIX = "com.mamhabit.personal.";
    private static final String TIMER = PREFIX + "TIMER";
    private static final String LEAVING = PREFIX + "LEAVING";
    private static final String REMIND = PREFIX + "REMIND";
    private static final String FOCUS_CHANNEL = "focus";
    private static final String COUNTDOWN_CHANNEL = "countdown";
    private static final String REMINDER_CHANNEL = "reminders";
    private static final int WARNING_ID = 1;
    private static final int TIMER_ID = 2;
    private static final int COUNTDOWN_ID = 3;

    static String language(Context context, String vi, String en) {
        return context.getSharedPreferences("settings", Context.MODE_PRIVATE).getBoolean("english", false) ? en : vi;
    }

    static boolean enabled(Context context) {
        return (Build.VERSION.SDK_INT < 33
                || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
                && context.getSystemService(NotificationManager.class).areNotificationsEnabled();
    }

    private static void notify(Context context, String channel, int id, String title, String body) {
        if (!enabled(context)) return;
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        String name = channel.equals(FOCUS_CHANNEL) ? "Focus & Rest" : language(context, "Nhắc thói quen", "Habit reminders");
        NotificationChannel settings = new NotificationChannel(channel, name, NotificationManager.IMPORTANCE_HIGH);
        if (channel.equals(FOCUS_CHANNEL)) {
            Uri sound = Uri.parse("android.resource://" + context.getPackageName() + "/" + R.raw.giot_nang);
            settings.setSound(sound, new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build());
        }
        manager.createNotificationChannel(settings);
        Notification notification = new Notification.Builder(context, channel)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title).setContentText(body).setStyle(new Notification.BigTextStyle().bigText(body))
                .setContentIntent(openApp(context)).setAutoCancel(true).build();
        manager.notify(id, notification);
    }

    private static PendingIntent openApp(Context context) {
        return PendingIntent.getActivity(context, 0, new Intent(context, MainActivity.class)
                        .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    private static void countdown(Context context, JSONObject session, long end) {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (session == null || !enabled(context) || end <= System.currentTimeMillis()) {
            manager.cancel(COUNTDOWN_ID);
            return;
        }
        NotificationChannel channel = new NotificationChannel(COUNTDOWN_CHANNEL,
                language(context, "Đồng hồ phiên", "Session countdown"), NotificationManager.IMPORTANCE_LOW);
        manager.createNotificationChannel(channel);
        String title = session.optBoolean("isBreak") ? language(context, "Đang nghỉ", "On a break")
                : language(context, "Đang tập trung", "Focusing");
        Notification notification = new Notification.Builder(context, COUNTDOWN_CHANNEL)
                .setSmallIcon(R.drawable.ic_notification).setContentTitle(title).setContentIntent(openApp(context))
                .setWhen(end).setShowWhen(true).setUsesChronometer(true).setChronometerCountDown(true)
                .setTimeoutAfter(end - System.currentTimeMillis()).setOnlyAlertOnce(true)
                .setOngoing(true).setVisibility(Notification.VISIBILITY_PUBLIC).build();
        manager.notify(COUNTDOWN_ID, notification);
    }

    static boolean exact(Context context) {
        return Build.VERSION.SDK_INT < 31 || context.getSystemService(AlarmManager.class).canScheduleExactAlarms();
    }

    private static void schedule(Context context, String action, long time) {
        AlarmManager manager = context.getSystemService(AlarmManager.class);
        PendingIntent intent = PendingIntent.getBroadcast(context, 0, new Intent(context, Alerts.class).setAction(action),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        if (time <= 0) {
            manager.cancel(intent);
            return;
        }
        try {
            if (exact(context)) {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, time, intent);
                return;
            }
        } catch (SecurityException e) {
            Log.w("Focuz", "Exact alarm access changed", e);
        }
        manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, time, intent);
    }

    static void syncSession(Context context, FocuzStore store) {
        JSONObject session = store.active();
        JSONObject departure = store.focus().optJSONObject("departure");
        boolean left = session != null && departure != null && !departure.has("lockedAt");
        long end = session == null ? 0 : time(session, "ends");
        long away = left ? time(departure, "date") : 0;
        long deadline = left ? away + GRACE : 0;
        schedule(context, TIMER, left ? Math.min(end, deadline) : end);
        boolean warn = left && (away + WARNING < end) && !departure.optBoolean("noticeShown");
        schedule(context, LEAVING, warn && enabled(context) ? away + WARNING : 0);
        if (!left) context.getSystemService(NotificationManager.class).cancel(WARNING_ID);
        countdown(context, session, end);
    }

    static String reconcile(Context context, FocuzStore store, long now) throws IOException {
        String status = due(store.focus(), now);
        if (status.isEmpty() || store.readError) return "";
        JSONObject session = store.active();
        JSONObject departure = store.focus().optJSONObject("departure");
        long recordedEnd = status.equals("interrupted") ? time(departure, "date") + GRACE : now;
        store.edit(next -> finish(next, recordedEnd, status));
        syncSession(context, store);
        boolean rest = session.optBoolean("isBreak");
        int minutes = session.optInt("minutes");
        String title = status.equals("interrupted") ? language(context, "Focus bị gián đoạn", "Focus interrupted")
                : rest ? language(context, "Hết giờ nghỉ", "Rest complete") : language(context, "Focus hoàn tất", "Focus complete");
        String body = status.equals("interrupted")
                ? language(context, "Mở Focuz để bắt đầu lại.", "Open Focuz to start again.")
                : rest ? language(context, "Bạn có thể bắt đầu phiên mới.", "You can start another session.")
                : language(context, "+" + minutes + " XP · +" + minutes + " xu", "+" + minutes + " XP · +" + minutes + " coins");
        notify(context, FOCUS_CHANNEL, TIMER_ID, title, body);
        return status;
    }

    static void warn(Context context, FocuzStore store, long now) throws IOException {
        JSONObject departure = store.focus().optJSONObject("departure");
        JSONObject session = store.active();
        if (departure == null || session == null || departure.has("lockedAt") || departure.optBoolean("noticeShown")
                || !enabled(context) || now < time(departure, "date") + WARNING
                || now >= Math.min(time(session, "ends"), time(departure, "date") + GRACE)) return;
        store.edit(next -> put(next.optJSONObject("focus").optJSONObject("departure"), "noticeShown", true));
        notify(context, FOCUS_CHANNEL, WARNING_ID, language(context, "Quay lại Focuz", "Return to Focuz"),
                language(context, "Phiên sẽ bị đặt lại nếu bạn không quay lại kịp.", "Your session will reset unless you return in time."));
    }

    private static final class Reminder {
        final String habit;
        final long time;

        Reminder(String habit, LocalDate date, int hour, int minute) {
            this.habit = habit;
            time = date.atTime(hour, minute).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli();
        }
    }

    private static List<Reminder> reminders(FocuzStore store, LocalDate day) {
        JSONObject state = store.state();
        List<Reminder> reminders = new ArrayList<>();
        if (state.optBoolean("reminderEnabled")) {
            reminders.add(new Reminder(null, day, state.optInt("reminderHour", 20), state.optInt("reminderMinute")));
        }
        for (JSONObject habit : rows(state, "habits")) {
            JSONObject reminder = habit.optJSONObject("reminder");
            if (reminder != null && scheduled(habit, day)) {
                reminders.add(new Reminder(habit.optString("title"), day, reminder.optInt("hour"), reminder.optInt("minute")));
            }
        }
        return reminders;
    }

    static void syncReminders(Context context, FocuzStore store, long now) {
        long next = Long.MAX_VALUE;
        if (!store.readError && enabled(context)) {
            LocalDate day = day(now);
            for (int offset = 0; offset <= 7 && next == Long.MAX_VALUE; offset++) {
                for (Reminder reminder : reminders(store, day.plusDays(offset))) {
                    if (reminder.time > now) next = Math.min(next, reminder.time);
                }
            }
        }
        context.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().putLong("nextReminder", next).apply();
        schedule(context, REMIND, next == Long.MAX_VALUE ? 0 : next);
    }

    @Override public void onReceive(Context context, Intent intent) {
        FocuzStore store = FocuzStore.get(context);
        long now = Instant.now().toEpochMilli();
        try {
            String action = intent.getAction();
            if (REMIND.equals(action)) {
                long scheduled = context.getSharedPreferences("settings", Context.MODE_PRIVATE).getLong("nextReminder", 0);
                if (scheduled > 0 && scheduled <= now && day(scheduled).equals(day(now))) {
                    int id = 100;
                    for (Reminder reminder : reminders(store, day(scheduled))) {
                        if (reminder.time < scheduled || reminder.time > now) continue;
                        notify(context, REMINDER_CHANNEL, id++, language(context, "Nhắc thói quen", "Habit reminder"),
                                reminder.habit == null ? language(context, "Đến giờ xem thói quen hôm nay.", "Time to check today's habits.")
                                        : reminder.habit);
                    }
                }
                syncReminders(context, store, now);
            } else if (LEAVING.equals(action)) {
                warn(context, store, now);
            } else if (TIMER.equals(action)) {
                reconcile(context, store, now);
            } else {
                reconcile(context, store, now);
                syncSession(context, store);
                syncReminders(context, store, now);
            }
        } catch (IOException e) {
            Log.e("Focuz", "Could not update persisted timer", e);
        }
    }
}
