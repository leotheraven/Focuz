package com.mamhabit.personal;

import static com.mamhabit.personal.FocuzStore.*;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.app.KeyguardManager;
import android.app.TimePickerDialog;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.provider.Settings;
import android.text.InputFilter;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.WindowInsets;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.Spinner;
import android.widget.ArrayAdapter;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.FormatStyle;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public final class MainActivity extends Activity {
    private static final int BG = 0xFFF4F5F0;
    private static final int INK = 0xFF203B31;
    private static final int MUTED = 0xFF53665B;
    private static final int GREEN = 0xFF285F49;
    private static final int MINT = 0xFFE3EEDC;
    private static final int GOLD = 0xFFF8EAD1;
    private static final int RUST = 0xFF934520;
    private static final int BORDER = 0xFFDFE4DB;
    private static final int EXPORT = 100;
    private static final int IMPORT = 101;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private FocuzStore store;
    private boolean english;
    private boolean visible;
    private boolean started;
    private int section;
    private int gardenTab;
    private int restMinutes = 5;
    private LocalDate displayedDay;
    private String displayedSession = "";
    private boolean displayedRest;
    private ScrollView scroll;
    private LinearLayout body;
    private TextView clock;
    private ProgressBar timerProgress;
    private String failedSaveSession = "";
    private final Runnable tick = this::tick;
    private final Runnable checkUnlocked = () -> {
        if (!started && unlocked()) leaveSession();
    };
    private final BroadcastReceiver screen = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            String action = intent.getAction();
            JSONObject session = store.active();
            JSONObject departure = store.focus().optJSONObject("departure");
            if (Intent.ACTION_SCREEN_OFF.equals(action) && session != null && departure != null
                    && !departure.has("lockedAt") && now() - time(departure, "date") <= 1_500) {
                if (save(next -> {
                    JSONObject left = next.optJSONObject("focus").optJSONObject("departure");
                    put(left, "lockedAt", date(now()));
                })) {
                    handler.removeCallbacks(tick);
                    Alerts.syncSession(MainActivity.this, store);
                }
            } else if (Intent.ACTION_USER_PRESENT.equals(action) || Intent.ACTION_SCREEN_ON.equals(action)) {
                handler.removeCallbacks(checkUnlocked);
                handler.postDelayed(checkUnlocked, 700);
            }
        }
    };

    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        store = FocuzStore.get(this);
        english = getPreferencesLanguage();
        if (saved != null) {
            section = saved.getInt("section");
            gardenTab = saved.getInt("gardenTab");
            restMinutes = saved.getInt("restMinutes", 5);
        }
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
                | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        IntentFilter filter = new IntentFilter(Intent.ACTION_SCREEN_OFF);
        filter.addAction(Intent.ACTION_SCREEN_ON);
        filter.addAction(Intent.ACTION_USER_PRESENT);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(screen, filter, Context.RECEIVER_NOT_EXPORTED);
        else registerReceiver(screen, filter);
        render(false);
    }

    @Override protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        out.putInt("section", section);
        out.putInt("gardenTab", gardenTab);
        out.putInt("restMinutes", restMinutes);
    }

    @Override protected void onStart() {
        super.onStart();
        started = true;
    }

    @Override protected void onResume() {
        super.onResume();
        visible = true;
        handler.removeCallbacks(tick);
        handler.removeCallbacks(checkUnlocked);
        settle();
        if (store.active() != null && store.focus().optJSONObject("departure") != null) {
            save(next -> next.optJSONObject("focus").remove("departure"));
        }
        Alerts.syncSession(this, store);
        Alerts.syncReminders(this, store, now());
        render(true);
        tick();
    }

    @Override protected void onPause() {
        super.onPause();
        visible = false;
        handler.removeCallbacks(tick);
    }

    @Override protected void onStop() {
        super.onStop();
        started = false;
        if (!isChangingConfigurations() && unlocked()) leaveSession();
        if (store.active() == null) handler.removeCallbacks(tick);
    }

    @Override protected void onDestroy() {
        unregisterReceiver(screen);
        handler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }

    private boolean unlocked() {
        return getSystemService(PowerManager.class).isInteractive()
                && !getSystemService(KeyguardManager.class).isKeyguardLocked();
    }

    private void leaveSession() {
        JSONObject session = store.active();
        if (session == null || session.optBoolean("isBreak") || store.readError) return;
        JSONObject left = store.focus().optJSONObject("departure");
        if (left != null && !left.has("lockedAt")) return;
        long now = now();
        if (now >= time(session, "ends")) {
            settle();
            return;
        }
        if (save(next -> put(next.optJSONObject("focus"), "departure",
                obj("sessionID", session.optString("id"), "date", date(now))))) {
            Alerts.syncSession(this, store);
            handler.removeCallbacks(tick);
            handler.postDelayed(tick, WARNING);
        }
    }

    private void tick() {
        settle();
        if (visible) {
            if (!today().equals(displayedDay) || !sessionId().equals(displayedSession)
                    || displayedRest != store.focus().optBoolean("awaitingRest")) render(true);
            updateClock();
        } else if (hasUnlockedDeparture()) {
            try {
                Alerts.warn(this, store, now());
            } catch (IOException e) {
                if (started) error();
            }
        }
        if (visible || hasUnlockedDeparture()) handler.postDelayed(tick, 250);
    }

    private boolean hasUnlockedDeparture() {
        JSONObject left = store.focus().optJSONObject("departure");
        return store.active() != null && left != null && !left.has("lockedAt");
    }

    private void settle() {
        try {
            Alerts.reconcile(this, store, now());
            showInterruption();
        } catch (IOException e) {
            if (visible && !sessionId().equals(failedSaveSession)) {
                failedSaveSession = sessionId();
                error();
            }
        }
    }

    private void showInterruption() {
        if (visible && !displayedSession.isEmpty() && store.active() == null) {
            JSONObject ended = find(store.focus(), "sessions", displayedSession);
            if (ended != null && ended.optString("status").equals("interrupted")) {
                toast(t("Focus bị gián đoạn. Bấm Bắt đầu để thử lại.", "Focus interrupted. Tap Start focus to try again."));
            }
        }
    }

    private String sessionId() {
        JSONObject session = store.active();
        return session == null ? "" : session.optString("id");
    }

    private static long now() { return System.currentTimeMillis(); }
    private String t(String vi, String en) { return english ? en : vi; }
    private String name(Item item) { return t(item.vi, item.en); }
    private Locale locale() { return english ? Locale.US : new Locale("vi", "VN"); }
    private String number(long value) { return String.format(locale(), "%,d", value); }
    private String coins(long value) { return number(value) + t(" xu", " coins"); }
    private boolean getPreferencesLanguage() { return getSharedPreferences("settings", MODE_PRIVATE).getBoolean("english", false); }
    private int dp(float value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    private void toast(String message) { Toast.makeText(this, message, Toast.LENGTH_SHORT).show(); }
    private void error() { toast(t("Không lưu được dữ liệu Focuz.", "Focuz could not save your data.")); }

    private boolean save(Edit edit) {
        try {
            store.edit(edit);
            return true;
        } catch (IOException e) {
            if (visible || started) error();
        } catch (IllegalArgumentException e) {
            toast(t("Dữ liệu đã thay đổi hoặc bạn chưa đủ xu.", "The data changed or you need more coins."));
        }
        return false;
    }

    private void change(Edit edit) {
        if (save(edit)) {
            Alerts.syncReminders(this, store, now());
            render(true);
        }
    }

    private GradientDrawable shape(int color, int radius, int border) {
        GradientDrawable result = new GradientDrawable();
        result.setColor(color);
        result.setCornerRadius(dp(radius));
        if (border != 0) result.setStroke(dp(1), border);
        return result;
    }

    private LinearLayout column() {
        LinearLayout result = new LinearLayout(this);
        result.setOrientation(LinearLayout.VERTICAL);
        return result;
    }

    private LinearLayout row() {
        LinearLayout result = new LinearLayout(this);
        result.setGravity(Gravity.CENTER_VERTICAL);
        return result;
    }

    private TextView text(String value, float size, int color, boolean bold) {
        TextView result = new TextView(this);
        result.setText(value);
        result.setTextSize(size);
        result.setTextColor(color);
        if (bold) result.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        return result;
    }

    private Button button(String label, boolean primary, Runnable action) {
        Button result = new Button(this);
        result.setAllCaps(false);
        result.setText(label);
        result.setTextSize(14);
        result.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        result.setTextColor(primary ? Color.WHITE : GREEN);
        result.setGravity(Gravity.CENTER);
        result.setMinHeight(dp(48));
        result.setMinimumHeight(dp(48));
        result.setMinWidth(0);
        result.setMinimumWidth(0);
        result.setPadding(dp(13), dp(7), dp(13), dp(7));
        result.setBackground(new RippleDrawable(ColorStateList.valueOf(0x30285F49),
                shape(primary ? GREEN : MINT, 15, 0), null));
        result.setOnClickListener(v -> action.run());
        return result;
    }

    private Button enabled(Button button, boolean enabled) {
        button.setEnabled(enabled);
        button.setAlpha(enabled ? 1f : .52f);
        return button;
    }

    private void add(LinearLayout layout, View view, int top) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.topMargin = dp(top);
        layout.addView(view, params);
    }

    private void pad(View view, int left, int top, int right, int bottom) {
        view.setPadding(dp(left), dp(top), dp(right), dp(bottom));
    }

    private void weight(LinearLayout layout, View view) {
        layout.addView(view, new LinearLayout.LayoutParams(0, -2, 1));
    }

    private void gap(LinearLayout row, int value) { row.addView(new View(this), dp(value), 1); }
    private void title(String value) {
        TextView heading = text(value, 30, INK, true);
        if (Build.VERSION.SDK_INT >= 28) heading.setAccessibilityHeading(true);
        add(body, heading, 0);
    }

    private void heading(String value) {
        TextView heading = text(value, 19, INK, true);
        if (Build.VERSION.SDK_INT >= 28) heading.setAccessibilityHeading(true);
        add(body, heading, 20);
    }

    private LinearLayout card(LinearLayout parent, int margin) {
        LinearLayout card = column();
        pad(card, 16, 14, 16, 16);
        card.setBackground(shape(Color.WHITE, 22, BORDER));
        add(parent, card, margin);
        return card;
    }

    private ProgressBar progress(int value, int max) {
        ProgressBar bar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        bar.setMax(Math.max(max, 1));
        bar.setProgress(Math.max(value, 0));
        bar.setProgressTintList(ColorStateList.valueOf(GREEN));
        bar.setProgressBackgroundTintList(ColorStateList.valueOf(MINT));
        return bar;
    }

    private void render(boolean preserveScroll) {
        int position = preserveScroll && scroll != null ? scroll.getScrollY() : 0;
        displayedDay = today();
        displayedSession = sessionId();
        boolean awaiting = store.focus().optBoolean("awaitingRest");
        if (awaiting && !displayedRest) restMinutes = 5;
        displayedRest = awaiting;
        clock = null;
        timerProgress = null;
        LinearLayout root = column();
        root.setBackgroundColor(BG);
        if (Build.VERSION.SDK_INT >= 35) {
            root.setOnApplyWindowInsetsListener((view, window) -> {
                android.graphics.Insets insets = window.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
                view.setPadding(insets.left, insets.top, insets.right, insets.bottom);
                return window;
            });
        }
        LinearLayout header = row();
        pad(header, 18, 5, 14, 5);
        TextView brand = text("Focuz", 26, GREEN, true);
        weight(header, brand);
        TextView balance = text("◉  " + number(store.coins()), 15, RUST, true);
        pad(balance, 12, 8, 12, 8);
        balance.setBackground(shape(GOLD, 40, 0));
        balance.setContentDescription(coins(store.coins()));
        header.addView(balance);
        gap(header, 8);
        Button options = button("⚙", false, () -> open(4));
        options.setTextSize(21);
        options.setContentDescription(t("Cài đặt", "Settings"));
        header.addView(options, dp(48), -2);
        add(root, header, 0);

        scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setClipToPadding(false);
        root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
        body = column();
        pad(body, 16, 10, 16, 24);
        scroll.addView(body);
        if (store.readError) {
            LinearLayout notice = card(body, 0);
            add(notice, text(t("Không đọc được dữ liệu. Hãy khôi phục bản sao lưu trong Cài đặt.",
                    "Saved data could not be read. Restore a backup in Settings."), 14, RUST, true), 0);
        }
        switch (section) {
            case 1: garden(); break;
            case 2: rewards(); break;
            case 3: history(); break;
            case 4: settings(); break;
            default: todayScreen();
        }
        LinearLayout navigation = row();
        navigation.setBackgroundColor(Color.WHITE);
        pad(navigation, 5, 6, 5, 6);
        String[] labels = {t("Hôm nay", "Today"), t("Khu vườn", "Garden"), t("Đổi quà", "Rewards"), t("Hành trình", "History")};
        String[] marks = {"◷", "❋", "◇", "▤"};
        for (int i = 0; i < labels.length; i++) {
            int index = i;
            Button tab = button(marks[i] + "\n" + labels[i], section == i, () -> open(index));
            tab.setTextSize(12);
            pad(tab, 3, 4, 3, 4);
            tab.setContentDescription(labels[i]);
            tab.setSelected(section == i);
            weight(navigation, tab);
            if (i < labels.length - 1) gap(navigation, 4);
        }
        View divider = new View(this);
        divider.setBackgroundColor(BORDER);
        root.addView(divider, -1, dp(1));
        add(root, navigation, 0);
        setContentView(root);
        if (position != 0) scroll.post(() -> scroll.scrollTo(0, position));
        updateClock();
    }

    private void open(int tab) {
        section = tab;
        render(false);
    }

    private void todayScreen() {
        LocalDate today = displayedDay;
        add(body, text(today.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL).withLocale(locale())), 14, MUTED, false), 0);
        title(t("Hôm nay", "Today"));
        List<JSONObject> habits = new ArrayList<>();
        int completed = 0;
        for (JSONObject habit : rows(store.state(), "habits")) {
            if (!scheduled(habit, today)) continue;
            habits.add(habit);
            if (complete(entry(store.state(), habit.optString("id"), today))) completed++;
        }
        LinearLayout stats = row();
        weight(stats, stat(number(store.focusedToday(today)), t("phút Focus", "focus minutes")));
        gap(stats, 8);
        weight(stats, stat(completed + "/" + habits.size(), t("thói quen", "habits done")));
        gap(stats, 8);
        weight(stats, stat(Integer.toString(level(store.xp(store.plant()))), t("cấp cây", "plant level")));
        add(body, stats, 12);
        focusCard();

        LinearLayout actions = row();
        weight(actions, text(t("Thói quen", "Habits"), 20, INK, true));
        boolean hasHabits = false;
        for (JSONObject habit : rows(store.state(), "habits")) if (activeHabit(habit)) hasHabits = true;
        if (hasHabits) actions.addView(button(t("Quản lý", "Manage"), false, this::manageHabits));
        gap(actions, 6);
        actions.addView(button(t("+ Thêm", "+ Add"), true, () -> editHabit(null)));
        add(body, actions, 20);
        if (habits.isEmpty()) add(card(body, 9), text(t("Hôm nay chưa có thói quen theo lịch.",
                "No habits are scheduled for today."), 15, MUTED, false), 0);
        for (JSONObject habit : habits) habitCard(habit, today);
        boolean claimed = has(store.state().optJSONArray("chests"), today.toString());
        if (canClaim(store.state(), today) || claimed) {
            LinearLayout chest = card(body, 10);
            add(chest, text(t("Rương ngày", "Daily reward") + "  ·  +25", 18, INK, true), 0);
            add(chest, claimed ? text(t("Đã nhận", "Claimed"), 14, MUTED, false)
                    : button(t("Mở rương", "Claim reward"), true, () -> change(next -> {
                        LocalDate day = today();
                        if (canClaim(next, day)) next.optJSONArray("chests").put(day.toString());
                    })), 7);
        }
    }

    private LinearLayout stat(String value, String label) {
        LinearLayout tile = column();
        tile.setBackground(shape(MINT, 14, 0));
        pad(tile, 10, 8, 7, 8);
        add(tile, text(value, 19, GREEN, true), 0);
        add(tile, text(label, 12, MUTED, false), 1);
        return tile;
    }

    private void focusCard() {
        JSONObject session = store.active();
        boolean waiting = store.focus().optBoolean("awaitingRest");
        boolean rest = waiting || (session != null && session.optBoolean("isBreak"));
        LinearLayout card = card(body, 12);
        LinearLayout header = row();
        weight(header, text(rest ? "Rest" : "Focus", 20, INK, true));
        if (session == null) {
            Button options = button(t("Tùy chọn", "Options"), false, this::focusOptions);
            header.addView(options);
        }
        add(card, header, 0);

        LinearLayout main = row();
        LinearLayout timer = column();
        clock = text("", 44, INK, true);
        clock.setTypeface(Typeface.MONOSPACE, Typeface.BOLD);
        clock.setMaxLines(1);
        clock.setAutoSizeTextTypeUniformWithConfiguration(23, 44, 1, android.util.TypedValue.COMPLEX_UNIT_SP);
        add(timer, clock, 0);
        if (session == null) {
            int minutes = rest ? restMinutes : store.focus().optInt("preferredMinutes", 25);
            LinearLayout duration = row();
            Button less = enabled(button("−", false, () -> setDuration(rest, minutes - 5)), minutes > (rest ? 5 : 10));
            less.setContentDescription(t("Giảm 5 phút", "Decrease by 5 minutes"));
            duration.addView(less, dp(48), -2);
            TextView unit = text(t("phút", "min"), 13, MUTED, false);
            unit.setGravity(Gravity.CENTER);
            weight(duration, unit);
            Button more = enabled(button("+", false, () -> setDuration(rest, minutes + 5)), minutes < (rest ? 60 : 180));
            more.setContentDescription(t("Tăng 5 phút", "Increase by 5 minutes"));
            duration.addView(more, dp(48), -2);
            add(timer, duration, 3);
        }
        add(timer, text(waiting ? t("Focus hoàn tất. Nghỉ khi sẵn sàng.", "Focus complete. Rest when ready.")
                : rest ? t("Đang nghỉ", "On a break")
                : session == null ? t("Strict · Hoàn tất để nhận thưởng", "Strict · Finish to earn rewards")
                : t("Đang tập trung · Rời app quá 10 giây sẽ reset", "Focusing · Leaving for 10 seconds resets the session"),
                12, MUTED, false), 7);
        weight(main, timer);
        gap(main, 12);
        GardenArt thumbnail = new GardenArt(this, store);
        thumbnail.setBackground(shape(MINT, 16, 0));
        thumbnail.setClipToOutline(true);
        main.addView(thumbnail, dp(getResources().getConfiguration().screenWidthDp < 350 ? 90 : 112), dp(104));
        add(card, main, 7);
        if (session != null) {
            timerProgress = progress(0, session.optInt("minutes") * 60);
            timerProgress.setContentDescription(t("Tiến độ phiên", "Session progress"));
            add(card, timerProgress, 9);
            add(card, button(t("Dừng phiên", "End session"), false, () -> confirm(
                    rest ? t("Dừng Rest?", "End rest?") : t("Dừng phiên Focus?", "End focus session?"),
                    rest ? "" : t("Phiên này sẽ không cộng xu hoặc XP.", "This session will earn zero coins and XP."),
                    t("Dừng phiên", "End session"), () -> {
                        settle();
                        if (store.active() != null && save(next -> FocuzStore.finish(next, now(), "cancelled"))) {
                            Alerts.syncSession(this, store);
                            render(true);
                        }
                    })), 8);
        } else {
            LinearLayout actions = row();
            weight(actions, button(rest ? t("Bắt đầu Rest", "Start rest") : t("Bắt đầu", "Start focus"), true,
                    () -> begin(rest, rest ? restMinutes : store.focus().optInt("preferredMinutes", 25))));
            if (waiting) {
                gap(actions, 8);
                actions.addView(button(t("Bỏ qua", "Skip"), false,
                        () -> change(next -> put(next.optJSONObject("focus"), "awaitingRest", false))));
            }
            add(card, actions, 12);
        }
    }

    private void updateClock() {
        if (clock == null) return;
        JSONObject session = store.active();
        int minutes = store.focus().optBoolean("awaitingRest") ? restMinutes : store.focus().optInt("preferredMinutes", 25);
        long seconds = session == null ? minutes * 60L : Math.max(0, Math.min(session.optInt("minutes") * 60L,
                (time(session, "ends") - now() + 999) / 1_000));
        String label = String.format(Locale.ROOT, "%02d:%02d", seconds / 60, seconds % 60);
        if (!label.contentEquals(clock.getText())) clock.setText(label);
        if (session != null && timerProgress != null) timerProgress.setProgress(timerProgress.getMax() - (int) seconds);
    }

    private void begin(boolean rest, int minutes) {
        if (save(next -> start(next, minutes, rest, now()))) {
            Alerts.syncSession(this, store);
            render(true);
        }
    }

    private void setDuration(boolean rest, int minutes) {
        if (rest) {
            restMinutes = Math.max(5, Math.min(60, minutes));
            render(true);
        } else change(next -> put(next.optJSONObject("focus"), "preferredMinutes", Math.max(10, Math.min(180, minutes))));
    }

    private void focusOptions() {
        String[] options = {t("Bật thông báo phiên", "Enable session notifications"), "Rest · 5 " + t("phút", "min"),
                "Rest · 10 " + t("phút", "min")};
        new AlertDialog.Builder(this).setTitle(t("Tùy chọn Focus", "Focus options")).setItems(options, (dialog, index) -> {
            if (index == 0) notificationPermission();
            else begin(true, index * 5);
        }).setNeutralButton(t("Quy tắc Strict", "Strict rules"), (dialog, which) ->
                new AlertDialog.Builder(this).setTitle(t("Strict luôn bật", "Strict is always on"))
                        .setMessage(t("Khóa màn hình vẫn tính giờ. Nếu rời app, bạn có 10 giây để quay lại. Thông báo nhắc sau khoảng 5 giây khi Android cho phép.",
                                "Screen locks keep the timer running. If you leave the app, you have 10 seconds to return. Android can show a warning after about 5 seconds."))
                        .setPositiveButton(t("Xong", "Done"), null).show())
                .setNegativeButton(t("Xong", "Done"), null).show();
    }

    private void confirm(String title, String message, String action, Runnable run) {
        new AlertDialog.Builder(this).setTitle(title).setMessage(message)
                .setNegativeButton(t("Hủy", "Cancel"), null)
                .setPositiveButton(action, (dialog, which) -> run.run()).show();
    }

    private void habitCard(JSONObject habit, LocalDate day) {
        String id = habit.optString("id");
        JSONObject entry = entry(store.state(), id, day);
        int count = entry == null ? 0 : entry.optInt("count");
        int target = entry == null ? habit.optInt("target") : entry.optInt("target");
        LinearLayout container = card(body, 9);
        LinearLayout line = row();
        TextView badge = text(habitMark(habit.optString("symbol")), 21, habitColor(habit.optString("color")), true);
        badge.setGravity(Gravity.CENTER);
        badge.setBackground(shape(BG, 15, 0));
        line.addView(badge, dp(42), dp(42));
        gap(line, 10);
        LinearLayout labels = column();
        add(labels, text(habit.optString("title"), 16, INK, true), 0);
        add(labels, text(count + "/" + target + " " + habit.optString("unit"), 13, MUTED, false), 2);
        weight(line, labels);
        gap(line, 5);
        Button menu = button("⋯", false, () -> habitMenu(habit, true));
        menu.setTextSize(21);
        menu.setContentDescription(t("Tùy chọn cho ", "Options for ") + habit.optString("title"));
        line.addView(menu, dp(48), -2);
        add(container, line, 0);
        add(container, progress(count, target), 4);
        boolean complete = count >= target;
        add(container, enabled(button(complete ? t("✓ Hoàn thành", "✓ Completed")
                : target == 1 ? t("Đánh dấu hoàn thành", "Mark complete") : t("+1", "+1"), !complete,
                () -> change(next -> check(next, id, today(), 1, now()))), !complete), 4);
    }

    private static final String[] SYMBOLS = {"leaf.fill", "drop.fill", "book.closed.fill", "figure.walk",
            "heart.fill", "moon.fill", "sun.max.fill", "pencil", "music.note", "sparkles", "flame.fill", "cup.and.saucer.fill"};
    private static final String[] SYMBOL_MARKS = {"❋", "◆", "▤", "↗", "♥", "☾", "☀", "✎", "♫", "✦", "▲", "☕"};
    private static final String[] COLORS = {"green", "blue", "purple", "orange"};

    private String habitMark(String id) {
        for (int i = 0; i < SYMBOLS.length; i++) if (SYMBOLS[i].equals(id)) return SYMBOL_MARKS[i];
        return SYMBOL_MARKS[0];
    }

    private int habitColor(String color) {
        switch (color) {
            case "blue": return 0xFF3F6E9A;
            case "purple": return 0xFF786090;
            case "orange": return RUST;
            default: return GREEN;
        }
    }

    private void manageHabits() {
        List<JSONObject> active = new ArrayList<>();
        List<String> labels = new ArrayList<>();
        for (JSONObject habit : rows(store.state(), "habits")) {
            if (!activeHabit(habit)) continue;
            active.add(habit);
            labels.add(habit.optString("title"));
        }
        new AlertDialog.Builder(this).setTitle(t("Quản lý thói quen", "Manage habits"))
                .setItems(labels.toArray(new String[0]), (dialog, index) -> habitMenu(active.get(index), false))
                .setNegativeButton(t("Xong", "Done"), null).show();
    }

    private void habitMenu(JSONObject habit, boolean today) {
        String id = habit.optString("id");
        boolean paused = habit.optBoolean("archived");
        String[] actions = {t("Sửa", "Edit"), paused ? t("Tiếp tục", "Resume") : t("Tạm dừng", "Pause"),
                t("Xóa", "Delete"), t("Giảm một lần", "Undo one check-in")};
        boolean undo = today && entry(store.state(), id, today()) != null;
        new AlertDialog.Builder(this).setTitle(habit.optString("title"))
                .setItems(java.util.Arrays.copyOf(actions, undo ? 4 : 3), (dialog, index) -> {
                    if (index == 0) editHabit(habit);
                    else if (index == 1) change(next -> put(find(next, "habits", id), "archived", !paused));
                    else if (index == 2) confirm(t("Xóa thói quen?", "Delete habit?"),
                            t("Lịch sử và số xu đã nhận được giữ lại.", "Your history and earned coins are saved."),
                            actions[2], () -> change(next -> {
                                JSONObject row = find(next, "habits", id);
                                put(row, "deleted", true);
                                put(row, "archived", true);
                            }));
                    else change(next -> check(next, id, today(), -1, now()));
                }).setNegativeButton(t("Hủy", "Cancel"), null).show();
    }

    private EditText field(String value, String hint, int max, boolean numeric) {
        EditText input = new EditText(this);
        input.setSingleLine();
        input.setInputType(numeric ? InputType.TYPE_CLASS_NUMBER : InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);
        input.setFilters(new InputFilter[] {new InputFilter.LengthFilter(max)});
        input.setHint(hint);
        input.setText(value);
        input.setContentDescription(hint);
        return input;
    }

    private int integer(EditText input) {
        try {
            return Integer.parseInt(input.getText().toString().trim());
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    private Spinner spinner(String[] labels, String[] values, String selected, String description) {
        Spinner view = new Spinner(this);
        ArrayAdapter<String> adapter = new ArrayAdapter<>(this, android.R.layout.simple_spinner_item, labels);
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        view.setAdapter(adapter);
        int index = java.util.Arrays.asList(values).indexOf(selected);
        view.setSelection(Math.max(0, index));
        view.setMinimumHeight(dp(48));
        view.setContentDescription(description);
        return view;
    }

    private String hours(int hour, int minute) { return String.format(Locale.ROOT, "%02d:%02d", hour, minute); }

    private void editHabit(JSONObject existing) {
        if (existing == null && rows(store.state(), "habits").size() >= 500) {
            toast(t("Đã đạt giới hạn 500 thói quen.", "The 500-habit limit has been reached."));
            return;
        }
        JSONObject old = existing == null ? newHabit("", 1, t("lần", "times"), "leaf.fill", "green") : existing;
        LinearLayout form = column();
        pad(form, 20, 6, 20, 12);
        ScrollView wrapper = new ScrollView(this);
        wrapper.addView(form);
        EditText name = field(old.optString("title"), t("Tên thói quen", "Habit name"), 70, false);
        EditText target = field(Integer.toString(old.optInt("target")), t("Mục tiêu 1–20", "Target 1–20"), 2, true);
        EditText unit = field(old.optString("unit"), t("Đơn vị", "Unit"), 20, false);
        add(form, name, 7);
        LinearLayout inputs = row();
        LinearLayout count = column();
        add(count, text(t("Mục tiêu (1–20)", "Target (1–20)"), 13, MUTED, true), 0);
        add(count, target, 0);
        weight(inputs, count);
        gap(inputs, 12);
        LinearLayout units = column();
        add(units, text(t("Đơn vị", "Unit"), 13, MUTED, true), 0);
        add(units, unit, 0);
        weight(inputs, units);
        add(form, inputs, 8);
        String[] iconNames = {t("❋ Lá", "❋ Leaf"), t("◆ Nước", "◆ Water"), t("▤ Sách", "▤ Book"),
                t("↗ Vận động", "↗ Movement"), t("♥ Trái tim", "♥ Heart"), t("☾ Trăng", "☾ Moon"),
                t("☀ Mặt trời", "☀ Sun"), t("✎ Bút", "✎ Pencil"), t("♫ Nhạc", "♫ Music"),
                t("✦ Sao", "✦ Stars"), t("▲ Lửa", "▲ Flame"), t("☕ Cốc", "☕ Cup")};
        String[] colorNames = {t("Xanh lá", "Green"), t("Xanh biển", "Blue"), t("Tím", "Purple"), t("Cam", "Orange")};
        Spinner icon = spinner(iconNames, SYMBOLS, old.optString("symbol"), t("Biểu tượng", "Icon"));
        Spinner color = spinner(colorNames, COLORS, old.optString("color"), t("Màu", "Color"));
        LinearLayout styles = row();
        weight(styles, icon);
        weight(styles, color);
        add(form, styles, 5);
        add(form, text(t("Lặp lại vào", "Repeat on"), 15, INK, true), 8);
        String[] weekdays = english ? new String[]{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
                : new String[]{"T2", "T3", "T4", "T5", "T6", "T7", "CN"};
        CheckBox[] checks = new CheckBox[7];
        LinearLayout days = row();
        for (int i = 0; i < weekdays.length; i++) {
            if (i == 4) {
                add(form, days, 2);
                days = row();
            }
            CheckBox day = new CheckBox(this);
            day.setText(weekdays[i]);
            day.setTextColor(INK);
            day.setChecked(has(old.optJSONArray("weekdays"), (i + 1) % 7 + 1));
            day.setMinimumHeight(dp(48));
            checks[i] = day;
            weight(days, day);
        }
        weight(days, new View(this));
        add(form, days, 2);
        CheckBox reminder = new CheckBox(this);
        reminder.setText(t("Nhắc thói quen", "Habit reminder"));
        reminder.setMinimumHeight(dp(48));
        JSONObject oldReminder = old.optJSONObject("reminder");
        reminder.setChecked(oldReminder != null);
        int[] time = {oldReminder == null ? 20 : oldReminder.optInt("hour"), oldReminder == null ? 0 : oldReminder.optInt("minute")};
        Button chooseTime = button(hours(time[0], time[1]), false, () -> {});
        chooseTime.setOnClickListener(v -> new TimePickerDialog(this, (view, hour, minute) -> {
            time[0] = hour;
            time[1] = minute;
            chooseTime.setText(hours(hour, minute));
            reminder.setChecked(true);
        }, time[0], time[1], true).show());
        LinearLayout reminderLine = row();
        weight(reminderLine, reminder);
        reminderLine.addView(chooseTime);
        add(form, reminderLine, 5);
        TextView error = text("", 13, RUST, true);
        add(form, error, 4);
        AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle(existing == null ? t("Thêm thói quen", "Add habit") : t("Sửa thói quen", "Edit habit"))
                .setView(wrapper).setNegativeButton(t("Hủy", "Cancel"), null)
                .setPositiveButton(t("Lưu", "Save"), null).create();
        dialog.setOnShowListener(ignored -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            JSONArray chosen = new JSONArray();
            for (int i = 0; i < checks.length; i++) if (checks[i].isChecked()) chosen.put((i + 1) % 7 + 1);
            String title = name.getText().toString().trim();
            String id = old.optString("id");
            JSONObject edited = obj("id", id, "created", old.optString("created"), "archived", old.optBoolean("archived"),
                    "title", title, "unit", unit.getText().toString().trim(), "target", integer(target), "weekdays", chosen,
                    "symbol", SYMBOLS[icon.getSelectedItemPosition()], "color", COLORS[color.getSelectedItemPosition()]);
            if (reminder.isChecked()) put(edited, "reminder", obj("hour", time[0], "minute", time[1]));
            if (!validHabit(edited)) {
                error.setText(t("Nhập tên, mục tiêu từ 1–20 và chọn ít nhất một ngày.",
                        "Enter a name, a target of 1–20, and at least one day."));
                return;
            }
            int plans = reminder.isChecked() ? chosen.length() : 0;
            for (JSONObject row : rows(store.state(), "habits")) {
                if (!row.optString("id").equals(id) && !row.optBoolean("deleted") && row.optJSONObject("reminder") != null) {
                    plans += row.optJSONArray("weekdays").length();
                }
            }
            if (plans > 60) {
                error.setText(t("Đã đạt giới hạn 60 lịch nhắc mỗi tuần.", "The limit is 60 weekly reminder schedules."));
                return;
            }
            if (save(next -> {
                JSONArray habits = next.optJSONArray("habits");
                for (int i = 0; i < habits.length(); i++) {
                    if (id.equals(habits.optJSONObject(i).optString("id"))) {
                        try {
                            habits.put(i, edited);
                            return;
                        } catch (org.json.JSONException e) {
                            throw new IllegalArgumentException(e);
                        }
                    }
                }
                habits.put(edited);
            })) {
                dialog.dismiss();
                Alerts.syncReminders(this, store, now());
                render(true);
                if (reminder.isChecked() && !Alerts.enabled(this)) notificationPermission();
            }
        }));
        dialog.show();
    }

    private void garden() {
        title(t("Khu vườn", "Garden"));
        String plant = store.plant();
        int xp = store.xp(plant);
        int level = level(xp);
        int stage = (level - 1) * 8 / 100;
        FrameLayout picture = new FrameLayout(this);
        picture.setBackground(shape(MINT, 22, 0));
        picture.setClipToOutline(true);
        picture.addView(new GardenArt(this, store), new FrameLayout.LayoutParams(-1, -1));
        LinearLayout plantLevel = column();
        pad(plantLevel, 12, 6, 12, 6);
        plantLevel.setBackground(shape(0xF2FFFFFF, 17, 0));
        LinearLayout bar = row();
        bar.addView(text(t("Cấp ", "Level ") + level + "/100", 12, GREEN, true));
        gap(bar, 8);
        int start = LEVELS[level - 1];
        int span = level == 100 ? 1 : LEVELS[level] - start;
        ProgressBar growth = progress(level == 100 ? span : xp - start, span);
        growth.setContentDescription(t("Tiến độ lên cấp cây", "Plant level progress"));
        weight(bar, growth);
        gap(bar, 8);
        bar.addView(text(number(xp) + " XP", 12, GREEN, true));
        add(plantLevel, bar, 0);
        FrameLayout.LayoutParams badge = new FrameLayout.LayoutParams(-1, -2, Gravity.TOP);
        badge.setMargins(dp(16), dp(12), dp(16), 0);
        picture.addView(plantLevel, badge);
        LinearLayout.LayoutParams frame = new LinearLayout.LayoutParams(-1, dp(240));
        frame.topMargin = dp(12);
        body.addView(picture, frame);
        String pet = store.state().optString("petName");
        add(body, text(pet + " · " + (english ? STAGES_EN[stage] : STAGES_VI[stage]), 15, GREEN, true), 9);
        fertilizer();

        LinearLayout tabs = row();
        String[] categories = {"Cây", "Nền", "Trang trí"};
        String[] labels = {t("Cây", "Plants"), t("Nền", "Scenery"), t("Trang trí", "Decor")};
        for (int i = 0; i < categories.length; i++) {
            int index = i;
            Button tab = button(labels[i], gardenTab == i, () -> {
                gardenTab = index;
                render(true);
            });
            tab.setSelected(gardenTab == i);
            weight(tabs, tab);
            if (i < categories.length - 1) gap(tabs, 6);
        }
        add(body, tabs, 15);
        String category = categories[gardenTab];
        if (gardenTab != 0 && store.focus().optJSONObject("decorations").has(category)) {
            add(body, button(t("Dùng mặc định", "Use default"), false,
                    () -> change(next -> next.optJSONObject("focus").optJSONObject("decorations").remove(category))), 9);
        }
        for (Item item : ITEMS) {
            if (!item.category.equals(category)) continue;
            boolean owned = store.owned(item.id);
            boolean selected = gardenTab == 0 ? plant.equals(item.id)
                    : store.focus().optJSONObject("decorations").optString(category).equals(item.id);
            LinearLayout container = card(body, 9);
            LinearLayout line = row();
            ImageView art = image(item.art());
            art.setBackground(shape(MINT, 14, 0));
            art.setClipToOutline(true);
            line.addView(art, dp(76), dp(76));
            gap(line, 12);
            LinearLayout copy = column();
            add(copy, text(name(item), 17, INK, true), 0);
            if (gardenTab == 0) {
                int points = store.xp(item.id);
                add(copy, text(t("Cấp ", "Level ") + level(points) + " · " + number(points) + " XP", 13, MUTED, false), 3);
            }
            add(copy, text(owned ? t("Đã sở hữu", "Owned") : coins(item.cost), 13, RUST, true), 3);
            weight(line, copy);
            add(container, line, 0);
            String action = selected ? t("Đang dùng", "Selected") : owned ? t("Sử dụng", "Use") : t("Mở khóa", "Unlock");
            add(container, enabled(button(action, !selected, () -> {
                Runnable select = () -> change(next -> choose(next, item, now()));
                if (owned) select.run();
                else confirm(t("Mở khóa vật phẩm?", "Unlock this item?"), name(item) + " · " + coins(item.cost), action, select);
            }), !selected && (owned || store.coins() >= item.cost)), 8);
        }
    }

    private ImageView image(String name) {
        ImageView art = new ImageView(this);
        art.setImageBitmap(GardenArt.bitmap(this, name));
        art.setScaleType(name.startsWith("garden-") ? ImageView.ScaleType.CENTER_CROP : ImageView.ScaleType.FIT_CENTER);
        art.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        return art;
    }

    private void fertilizer() {
        String id = store.plant();
        int amount = Math.max(0, Math.min(25, MAX_XP - store.xp(id)));
        int cost = amount * 2;
        String plant = name(item(id));
        LinearLayout panel = card(body, 12);
        add(panel, text(t("Phân bón", "Fertilizer"), 18, INK, true), 0);
        String detail = amount == 0 ? t("Cây đã đạt cấp tối đa.", "This plant is at max level.")
                : plant + " · +" + amount + " XP · " + coins(cost);
        add(panel, text(detail, 14, MUTED, false), 4);
        String action = t("Mua và bón", "Buy and fertilize");
        add(panel, enabled(button(action, true, () ->
                confirm(t("Bón phân cho ", "Fertilize ") + plant + "?", detail, action,
                        () -> change(next -> fertilize(next, id, amount, now())))), amount > 0 && store.coins() >= cost), 9);
    }

    private void rewards() {
        title(t("Đổi quà", "Rewards"));
        fertilizer();
        LinearLayout header = row();
        weight(header, text(t("Phần thưởng", "Rewards"), 19, INK, true));
        header.addView(button(t("+ Thêm quà", "+ Add reward"), false, this::addReward));
        add(body, header, 16);
        for (Item item : REWARDS) rewardRow(item);
        for (JSONObject row : rows(store.state(), "customRewards")) {
            String title = row.optString("title");
            rewardRow(new Item(row.optString("id"), title, title, "Reward", row.optInt("cost")));
        }

        heading(t("Lịch sử đổi quà", "Redemption history"));
        List<JSONObject> entries = redemptionHistory(store.state());
        if (entries.isEmpty()) add(card(body, 8), text(t("Chưa đổi quà.", "No redemptions yet."), 15, MUTED, false), 0);
        for (JSONObject row : entries) {
            boolean isFertilizer = row.has("plantID");
            String title = isFertilizer ? t("Phân bón · ", "Fertilizer · ") + name(item(row.optString("plantID")))
                    : redemptionTitle(row);
            String detail = readableDay(day(time(row, "date"))) + " · −" + coins(row.optInt("cost"));
            if (isFertilizer) detail += " · +" + row.optInt("xp") + " XP";
            LinearLayout panel = card(body, 8);
            add(panel, text(title, 16, INK, true), 0);
            add(panel, text(detail, 13, MUTED, false), 4);
        }
    }

    private String redemptionTitle(JSONObject row) {
        String id = row.optString("rewardID");
        Item item = item(id);
        if (item != null) return name(item);
        for (Item reward : REWARDS) if (reward.id.equals(id)) return name(reward);
        return row.optString("title");
    }

    private void rewardRow(Item reward) {
        boolean decoration = reward.category.equals("Equip");
        boolean owned = decoration && store.owned(reward.id);
        boolean selected = owned && store.state().optString("equipped").equals(reward.id);
        LinearLayout panel = card(body, 8);
        add(panel, text(name(reward), 17, INK, true), 0);
        add(panel, text(owned ? t("Đã sở hữu", "Owned") : coins(reward.cost), 13, RUST, true), 3);
        String action = selected ? t("Đang dùng", "Selected") : owned ? t("Sử dụng", "Use") : t("Đổi quà", "Redeem");
        add(panel, enabled(button(action, !selected, () -> {
            Runnable redeem = () -> change(next -> {
                if (!owned) redeem(next, reward.id, reward.vi, reward.cost, now());
                if (decoration) put(next, "equipped", reward.id);
            });
            if (owned) redeem.run();
            else confirm(t("Đổi phần thưởng?", "Redeem reward?"), name(reward) + " · " + coins(reward.cost), action, redeem);
        }), !selected && (owned || store.coins() >= reward.cost)), 8);
        if (selected) add(panel, button(t("Dùng vườn mặc định", "Use default garden"), false,
                () -> change(next -> put(next, "equipped", "original"))), 6);
    }

    private void addReward() {
        if (rows(store.state(), "customRewards").size() >= 500) {
            toast(t("Đã đạt giới hạn 500 phần thưởng.", "The 500-reward limit has been reached."));
            return;
        }
        LinearLayout form = column();
        pad(form, 20, 6, 20, 10);
        EditText name = field("", t("Tên phần thưởng", "Reward name"), 70, false);
        EditText price = field("", t("Giá 10–10.000 xu", "Cost 10–10,000 coins"), 5, true);
        add(form, name, 0);
        add(form, price, 6);
        AlertDialog dialog = new AlertDialog.Builder(this).setTitle(t("Thêm phần thưởng", "Add reward"))
                .setView(form).setNegativeButton(t("Hủy", "Cancel"), null)
                .setPositiveButton(t("Lưu", "Save"), null).create();
        dialog.setOnShowListener(ignored -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            String title = name.getText().toString().trim();
            int cost = integer(price);
            if (title.isEmpty()) {
                name.setError(t("Nhập tên phần thưởng.", "Enter a reward name."));
            } else if (cost < 10 || cost > 10_000) {
                price.setError(t("Giá cần từ 10 đến 10.000 xu.", "Use a price from 10 to 10,000 coins."));
            } else if (save(next -> next.optJSONArray("customRewards").put(obj("id", uuid(), "title", title,
                    "detail", "Phần thưởng bạn tự dành cho mình", "symbol", "gift.fill", "cost", cost,
                    "custom", true, "decoration", false)))) {
                dialog.dismiss();
                render(true);
            }
        }));
        dialog.show();
    }

    private String readableDay(LocalDate day) {
        return day.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale()));
    }

    private void history() {
        title(t("Hành trình", "History"));
        LocalDate today = displayedDay;
        java.util.Map<String, Integer> counts = new java.util.HashMap<>();
        for (JSONObject row : rows(store.state(), "checkIns")) {
            if (!complete(row)) continue;
            counts.merge(row.optString("day"), 1, Integer::sum);
        }
        LinearLayout calendar = card(body, 12);
        add(calendar, text(t("28 ngày gần nhất", "Last 28 days"), 18, INK, true), 0);
        for (int week = 0; week < 4; week++) {
            LinearLayout days = row();
            for (int index = 0; index < 7; index++) {
                LocalDate day = today.minusDays(27 - week * 7L - index);
                int count = counts.getOrDefault(day.toString(), 0);
                LinearLayout cell = column();
                TextView date = text(Integer.toString(day.getDayOfMonth()), 14, count == 0 ? MUTED : Color.WHITE, true);
                date.setGravity(Gravity.CENTER);
                date.setMinHeight(dp(35));
                date.setBackground(shape(count == 0 ? BG : GREEN, 10, 0));
                add(cell, date, 0);
                TextView total = text(count == 0 ? "·" : number(count), 12, MUTED, false);
                total.setGravity(Gravity.CENTER);
                add(cell, total, 2);
                cell.setContentDescription(readableDay(day) + " · " + count + t(" thói quen hoàn thành", " habits completed"));
                date.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
                total.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
                weight(days, cell);
                if (index < 6) gap(days, 5);
            }
            add(calendar, days, 9);
        }
        add(calendar, text(t("Số dưới mỗi ô là số thói quen đã hoàn thành.", "Numbers show completed habits."), 13, MUTED, false), 9);
        heading(t("Chuỗi hiện tại", "Current streaks"));
        boolean any = false;
        for (JSONObject habit : rows(store.state(), "habits")) {
            if (!activeHabit(habit)) continue;
            any = true;
            LinearLayout panel = card(body, 8);
            LinearLayout line = row();
            weight(line, text(habitMark(habit.optString("symbol")) + "  " + habit.optString("title"), 16, INK, true));
            int days = streak(store.state(), habit, today);
            line.addView(text(days + t(" ngày", days == 1 ? " day" : " days"), 14, RUST, true));
            add(panel, line, 0);
        }
        if (!any) add(card(body, 8), text(t("Thêm thói quen ở mục Hôm nay.", "Add a habit on the Today screen."), 15, MUTED, false), 0);
        heading(t("Những lần gần đây", "Recent activity"));
        List<JSONObject> entries = recentActivity(store.state());
        if (entries.isEmpty()) add(card(body, 8), text(t("Chưa có hoạt động.", "No activity yet."), 15, MUTED, false), 0);
        for (JSONObject row : entries) {
            LinearLayout panel = card(body, 8);
            add(panel, text("✓  " + row.optString("title"), 16, INK, true), 0);
            add(panel, text(readableDay(LocalDate.parse(row.optString("day"))), 13, MUTED, false), 3);
        }
    }

    private void settings() {
        title(t("Cài đặt", "Settings"));
        LinearLayout language = card(body, 12);
        add(language, text(t("Ngôn ngữ", "Language"), 18, INK, true), 0);
        LinearLayout languages = row();
        weight(languages, button("Tiếng Việt", !english, () -> language(false)));
        gap(languages, 8);
        weight(languages, button("English", english, () -> language(true)));
        add(language, languages, 9);

        LinearLayout plant = card(body, 10);
        add(plant, text(t("Tên cây", "Plant name"), 18, INK, true), 0);
        EditText pet = field(store.state().optString("petName"), t("Tên cây", "Plant name"), 24, false);
        add(plant, pet, 5);
        add(plant, button(t("Lưu tên", "Save name"), false, () -> {
            String name = pet.getText().toString().trim();
            if (name.isEmpty()) pet.setError(t("Nhập tên cây.", "Enter a plant name."));
            else change(next -> put(next, "petName", name));
        }), 6);

        LinearLayout reminders = card(body, 10);
        add(reminders, text(t("Thông báo", "Notifications"), 18, INK, true), 0);
        add(reminders, button(Alerts.enabled(this) ? t("Cài đặt thông báo Android", "Android notification settings")
                : t("Bật thông báo", "Enable notifications"), false, this::notificationPermission), 9);
        if (Build.VERSION.SDK_INT >= 31 && !Alerts.exact(this)) {
            add(reminders, button(t("Cho phép báo đúng giờ", "Allow exact alarms"), false, () ->
                    startActivity(new Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:" + getPackageName())))), 7);
            add(reminders, text(t("Khi quyền này tắt, Android có thể gửi thông báo trễ lúc chạy nền.",
                    "When exact alarms are off, Android can delay background alerts."), 13, MUTED, false), 5);
        }
        JSONObject state = store.state();
        int hour = state.optInt("reminderHour");
        int minute = state.optInt("reminderMinute");
        boolean daily = state.optBoolean("reminderEnabled");
        String label = t("Nhắc hằng ngày", "Daily reminder");
        add(reminders, button(daily ? label + " · " + hours(hour, minute) : t("Đặt giờ nhắc hằng ngày", "Set daily reminder"),
                false, () -> new TimePickerDialog(this, (view, h, m) -> {
                    change(next -> {
                        put(next, "reminderEnabled", true);
                        put(next, "reminderHour", h);
                        put(next, "reminderMinute", m);
                    });
                    if (!Alerts.enabled(this)) notificationPermission();
                }, hour, minute, true).show()), 8);
        if (daily) add(reminders, button(t("Tắt nhắc hằng ngày", "Turn off daily reminder"), false,
                () -> change(next -> put(next, "reminderEnabled", false))), 6);

        heading(t("Thói quen tạm dừng", "Paused habits"));
        boolean hasPaused = false;
        for (JSONObject habit : rows(state, "habits")) {
            if (!habit.optBoolean("archived") || habit.optBoolean("deleted")) continue;
            hasPaused = true;
            LinearLayout paused = card(body, 7);
            add(paused, button(habit.optString("title"), false, () -> habitMenu(habit, false)), 0);
        }
        if (!hasPaused) add(body, text(t("Chưa có thói quen tạm dừng.", "No paused habits."), 14, MUTED, false), 6);

        LinearLayout backup = card(body, 15);
        add(backup, text(t("Sao lưu dữ liệu", "Backup"), 18, INK, true), 0);
        add(backup, enabled(button(t("Xuất bản sao lưu", "Export backup"), false, () -> documents(true)), !store.readError), 9);
        add(backup, button(t("Khôi phục bản sao lưu", "Restore backup"), false, () ->
                confirm(t("Khôi phục dữ liệu?", "Restore data?"),
                        t("Bản sao lưu sẽ thay thế dữ liệu Focuz hiện tại.", "This backup will replace your current Focuz data."),
                        t("Chọn tệp", "Choose file"), () -> documents(false))), 7);

        LinearLayout rules = card(body, 12);
        add(rules, text(t("Cách nhận thưởng", "Earning rewards"), 18, INK, true), 0);
        add(rules, text(t("Thói quen: +10 xu mỗi ngày.\nRương ngày: +25 xu.\nFocus hoàn tất: +1 XP và +1 xu mỗi phút.\nPhân bón: 50 xu cho 25 XP.",
                "Habits: +10 coins per day.\nDaily reward: +25 coins.\nCompleted Focus: +1 XP and +1 coin per minute.\nFertilizer: 50 coins for 25 XP."), 14, MUTED, false), 7);
        TextView version = text("Focuz 2.14", 13, MUTED, false);
        version.setGravity(Gravity.CENTER);
        add(body, version, 15);
    }

    private void language(boolean next) {
        english = next;
        getSharedPreferences("settings", MODE_PRIVATE).edit().putBoolean("english", next).apply();
        render(true);
    }

    private void notificationPermission() {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                && (!getSharedPreferences("settings", MODE_PRIVATE).getBoolean("askedNotifications", false)
                || shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS))) {
            getSharedPreferences("settings", MODE_PRIVATE).edit().putBoolean("askedNotifications", true).apply();
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1);
        } else {
            startActivity(new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName()));
        }
    }

    @Override public void onRequestPermissionsResult(int request, String[] permissions, int[] results) {
        super.onRequestPermissionsResult(request, permissions, results);
        Alerts.syncSession(this, store);
        Alerts.syncReminders(this, store, now());
        render(true);
    }

    private void documents(boolean export) {
        Intent picker = new Intent(export ? Intent.ACTION_CREATE_DOCUMENT : Intent.ACTION_OPEN_DOCUMENT);
        picker.addCategory(Intent.CATEGORY_OPENABLE);
        picker.setType(export ? "application/json" : "*/*");
        if (export) picker.putExtra(Intent.EXTRA_TITLE, "Focuz-" + today() + ".json");
        startActivityForResult(picker, export ? EXPORT : IMPORT);
    }

    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (result != RESULT_OK || data == null || data.getData() == null || (request != EXPORT && request != IMPORT)) return;
        Uri uri = data.getData();
        try {
            if (request == EXPORT) {
                byte[] bytes = store.backup();
                try (OutputStream output = getContentResolver().openOutputStream(uri, "wt")) {
                    if (output == null) throw new IOException();
                    output.write(bytes);
                }
                toast(t("Đã xuất bản sao lưu.", "Backup exported."));
            } else {
                byte[] bytes;
                try (InputStream input = getContentResolver().openInputStream(uri)) {
                    if (input == null) throw new IOException();
                    ByteArrayOutputStream buffer = new ByteArrayOutputStream();
                    byte[] chunk = new byte[8192];
                    int size;
                    while ((size = input.read(chunk)) != -1) {
                        if (buffer.size() + size > 20_000_000) throw new IOException();
                        buffer.write(chunk, 0, size);
                    }
                    bytes = buffer.toByteArray();
                }
                store.restore(bytes, now());
                Alerts.syncSession(this, store);
                Alerts.syncReminders(this, store, now());
                render(false);
                toast(t("Đã khôi phục bản sao lưu.", "Backup restored."));
            }
        } catch (IOException | org.json.JSONException | SecurityException e) {
            toast(request == EXPORT ? t("Không xuất được bản sao lưu.", "Could not export the backup.")
                    : t("Không đọc được bản sao lưu Focuz. Giới hạn 20 MB.", "Could not read the Focuz backup. The limit is 20 MB."));
        }
    }

    @Override public void onBackPressed() {
        if (section != 0) open(0);
        else super.onBackPressed();
    }
}
