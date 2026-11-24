package com.mamhabit.personal;

import android.content.Context;
import android.util.AtomicFile;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

final class FocuzStore {
    static final int MAX_XP = 20_000;
    static final int REVISION = 3;
    private static final int HISTORY_LIMIT = 20;
    static final long WARNING = 5_000;
    static final long GRACE = 10_000;
    private static final long APPLE_EPOCH = 978_307_200_000L;
    static final int[] LEVELS = levels();
    static final String[] STAGES_VI = {"Chồi non", "Lá non", "Cây nhỏ", "Vươn cao",
            "Tán xanh", "Tỏa bóng", "Sum suê", "Trưởng thành"};
    static final String[] STAGES_EN = {"Sprout", "First leaves", "Sapling", "Growing tall",
            "Leafy canopy", "Shady tree", "Flourishing", "Fully grown"};

    static final class Item {
        final String id, vi, en, category;
        final int cost;

        Item(String id, String vi, String en, String category, int cost) {
            this.id = id;
            this.vi = vi;
            this.en = en;
            this.category = category;
            this.cost = cost;
        }

        String art() {
            if (category.equals("Cây")) return "tree-" + id + "-3";
            return (category.equals("Nền") ? "garden-" : "deco-") + id;
        }
    }

    static final List<Item> ITEMS = Collections.unmodifiableList(Arrays.asList(
            new Item("sprout", "Cây xanh", "Green sprout", "Cây", 0),
            new Item("cactus", "Xương rồng", "Cactus", "Cây", 240),
            new Item("sunflower", "Hướng dương", "Sunflower", "Cây", 360),
            new Item("cherry", "Anh đào", "Cherry blossom", "Cây", 540),
            new Item("pine", "Thông xanh", "Pine", "Cây", 720),
            new Item("orange", "Cam ngọt", "Orange tree", "Cây", 900),
            new Item("mushroom", "Nấm cổ tích", "Mushroom", "Cây", 1140),
            new Item("bonsai", "Bonsai", "Bonsai", "Cây", 1500),
            new Item("nightSky", "Đêm đầy sao", "Starry night", "Nền", 360),
            new Item("sunset", "Hoàng hôn", "Sunset", "Nền", 480),
            new Item("snow", "Vườn tuyết", "Snow garden", "Nền", 660),
            new Item("butterfly", "Bướm ghé thăm", "Butterflies", "Trang trí", 300),
            new Item("lantern", "Đèn lồng", "Lantern", "Trang trí", 420),
            new Item("fence", "Hàng rào gỗ", "Wooden fence", "Trang trí", 540),
            new Item("stars", "Bụi sao", "Stardust", "Trang trí", 780)
    ));
    static final List<Item> REWARDS = Collections.unmodifiableList(Arrays.asList(
            new Item("night", "Vườn đom đóm", "Firefly garden", "Equip", 360),
            new Item("rainbow", "Vườn cầu vồng", "Rainbow garden", "Equip", 600),
            new Item("coffee", "Một ly yêu thích", "A favorite drink", "Reward", 240),
            new Item("movie", "Một tối xem phim", "Movie night", "Reward", 450)
    ));

    interface Edit { void apply(JSONObject next); }

    private static FocuzStore instance;
    private final AtomicFile file;
    private JSONObject state;
    boolean readError;

    static FocuzStore get(Context context) {
        if (instance == null) instance = new FocuzStore(context.getApplicationContext());
        return instance;
    }

    private FocuzStore(Context context) {
        File path = new File(context.getFilesDir(), "state.json");
        file = new AtomicFile(path);
        try {
            if (path.exists() || new File(path.getPath() + ".bak").exists()) {
                state = decode(file.readFully());
                if (migrateHistory(state)) write(state);
                return;
            }
            state = initial();
            write(state);
        } catch (IOException | JSONException | IllegalArgumentException e) {
            state = initial();
            readError = true;
        }
    }

    JSONObject state() { return state; }
    JSONObject focus() { return state.optJSONObject("focus"); }
    JSONObject active() { return focus().optJSONObject("active"); }
    String plant() { return focus().optString("selectedPlant"); }
    String backdrop() {
        return focus().optJSONObject("decorations").optString("Nền",
                state.optString("equipped").equals("night") ? "nightSky" : "day");
    }
    String decoration() { return focus().optJSONObject("decorations").optString("Trang trí"); }
    int xp(String id) { return points(focus().optJSONObject("growth"), id); }
    long coins() { return coins(state); }
    boolean owned(String id) { return id.equals("sprout") || owned(state, id); }

    static Item item(String id) {
        for (Item item : ITEMS) if (item.id.equals(id)) return item;
        return null;
    }

    void edit(Edit edit) throws IOException {
        if (readError) throw new IOException("Unreadable state");
        JSONObject next;
        try {
            next = new JSONObject(state.toString());
        } catch (JSONException e) {
            throw new IOException(e);
        }
        edit.apply(next);
        write(next);
        state = next;
    }

    private void write(JSONObject next) throws IOException {
        FileOutputStream stream = file.startWrite();
        try {
            stream.write(next.toString().getBytes(StandardCharsets.UTF_8));
            file.finishWrite(stream);
        } catch (IOException | RuntimeException e) {
            file.failWrite(stream);
            throw e;
        }
    }

    byte[] backup() throws IOException {
        if (readError) throw new IOException("Unreadable state");
        return state.toString().getBytes(StandardCharsets.UTF_8);
    }

    void restore(byte[] bytes, long now) throws JSONException, IOException {
        JSONObject next = decode(bytes);
        migrateHistory(next);
        JSONObject focus = next.optJSONObject("focus");
        if (focus.optJSONObject("active") != null) finish(next, now, "cancelled");
        focus.remove("departure");
        put(next, "reminderEnabled", false);
        write(next);
        state = next;
        readError = false;
    }

    static JSONObject obj(Object... fields) {
        JSONObject object = new JSONObject();
        for (int i = 0; i < fields.length; i += 2) put(object, (String) fields[i], fields[i + 1]);
        return object;
    }

    static void put(JSONObject object, String key, Object value) {
        try {
            object.put(key, value);
        } catch (JSONException e) {
            throw new IllegalArgumentException(e);
        }
    }

    static List<JSONObject> rows(JSONObject object, String key) {
        List<JSONObject> result = new ArrayList<>();
        JSONArray values = object.optJSONArray(key);
        if (values != null) {
            for (int i = 0; i < values.length(); i++) {
                JSONObject row = values.optJSONObject(i);
                if (row != null) result.add(row);
            }
        }
        return result;
    }

    static JSONObject find(JSONObject object, String key, String id) {
        for (JSONObject row : rows(object, key)) if (row.optString("id").equalsIgnoreCase(id)) return row;
        return null;
    }

    static String uuid() { return UUID.randomUUID().toString().toUpperCase(java.util.Locale.ROOT); }
    static LocalDate today() { return LocalDate.now(); }
    static LocalDate day(long millis) {
        return Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).toLocalDate();
    }
    static double date(long millis) { return (millis - APPLE_EPOCH) / 1000.0; }
    static long time(JSONObject row, String field) {
        return APPLE_EPOCH + Math.round(1000 * row.optDouble(field, 0));
    }

    static int weekday(LocalDate day) { return day.getDayOfWeek().getValue() % 7 + 1; }
    static boolean has(JSONArray array, Object value) {
        for (int i = 0; i < array.length(); i++) if (value.equals(array.opt(i))) return true;
        return false;
    }

    static boolean activeHabit(JSONObject habit) {
        return !habit.optBoolean("archived") && !habit.optBoolean("deleted");
    }

    static boolean scheduled(JSONObject habit, LocalDate day) {
        return activeHabit(habit) && habit.optString("created").compareTo(day.toString()) <= 0
                && has(habit.optJSONArray("weekdays"), weekday(day));
    }

    static JSONObject entry(JSONObject state, String id, LocalDate day) {
        String date = day.toString();
        for (JSONObject row : rows(state, "checkIns")) {
            if (row.optString("habitID").equalsIgnoreCase(id) && row.optString("day").equals(date)) return row;
        }
        return null;
    }

    static boolean complete(JSONObject entry) {
        return entry != null && entry.optInt("count") >= entry.optInt("target");
    }

    static boolean canClaim(JSONObject state, LocalDate day) {
        if (has(state.optJSONArray("chests"), day.toString())) return false;
        boolean hasHabits = false;
        for (JSONObject habit : rows(state, "habits")) {
            if (!scheduled(habit, day)) continue;
            hasHabits = true;
            if (!complete(entry(state, habit.optString("id"), day))) return false;
        }
        return hasHabits;
    }

    static void check(JSONObject state, String id, LocalDate day, int change, long now) {
        JSONObject habit = find(state, "habits", id);
        if (habit == null || !scheduled(habit, day)) return;
        JSONObject entry = entry(state, id, day);
        if (entry == null && change > 0) {
            entry = obj("habitID", id, "day", day.toString(), "count", 0,
                    "target", habit.optInt("target"), "rewarded", false);
            state.optJSONArray("checkIns").put(entry);
        }
        if (entry == null) return;
        boolean wasComplete = complete(entry);
        put(entry, "count", Math.min(entry.optInt("target"), Math.max(0, entry.optInt("count") + change)));
        if (complete(entry) && !wasComplete) {
            put(entry, "rewarded", true);
            put(entry, "title", habit.optString("title"));
            put(entry, "completedAt", date(now));
            pruneActivity(state);
        } else if (!complete(entry) && wasComplete) {
            entry.remove("title");
            entry.remove("completedAt");
        }
    }

    static List<JSONObject> recentActivity(JSONObject state) {
        List<JSONObject> entries = rows(state, "checkIns");
        entries.removeIf(row -> !complete(row) || row.isNull("title"));
        Collections.reverse(entries);
        entries.sort((a, b) -> {
            int day = b.optString("day").compareTo(a.optString("day"));
            if (day != 0) return day;
            return Double.compare(b.optDouble("completedAt", Double.NEGATIVE_INFINITY),
                    a.optDouble("completedAt", Double.NEGATIVE_INFINITY));
        });
        return entries;
    }

    private static void pruneActivity(JSONObject state) {
        List<JSONObject> recent = recentActivity(state);
        Set<JSONObject> keep = new HashSet<>(recent.subList(0, Math.min(HISTORY_LIMIT, recent.size())));
        // Check-ins still drive calendar counts, streaks and once-per-day rewards.
        for (JSONObject row : rows(state, "checkIns")) {
            if (keep.contains(row)) continue;
            row.remove("title");
            row.remove("completedAt");
        }
    }

    static int streak(JSONObject state, JSONObject habit, LocalDate today) {
        String id = habit.optString("id");
        Set<String> completed = new HashSet<>();
        for (JSONObject row : rows(state, "checkIns")) {
            if (row.optString("habitID").equalsIgnoreCase(id) && complete(row)) completed.add(row.optString("day"));
        }
        int count = 0;
        LocalDate first = LocalDate.parse(habit.optString("created"));
        for (LocalDate day = today; !day.isBefore(first); day = day.minusDays(1)) {
            if (!has(habit.optJSONArray("weekdays"), weekday(day))) continue;
            if (completed.contains(day.toString())) count++;
            else if (!day.equals(today)) break;
        }
        return count;
    }

    private static long coinsBeforeOlderSpending(JSONObject state) {
        long total = state.optJSONArray("chests").length() * 25L;
        for (JSONObject row : rows(state, "checkIns")) if (row.optBoolean("rewarded")) total += 10;
        for (JSONObject session : rows(state.optJSONObject("focus"), "sessions")) {
            if (doneFocus(session)) total += session.optInt("minutes");
        }
        for (JSONObject row : rows(state, "redemptions")) total -= row.optInt("cost");
        for (JSONObject row : rows(state, "fertilizations")) total -= row.optInt("cost");
        return total;
    }

    private static long coins(JSONObject state) {
        return coinsBeforeOlderSpending(state) - state.optLong("olderRewardSpending");
    }

    private static boolean owned(JSONObject state, String id) {
        JSONArray olderUnlocks = state.optJSONArray("olderUnlocks");
        if (olderUnlocks != null && has(olderUnlocks, id)) return true;
        for (JSONObject row : rows(state, "redemptions")) if (row.optString("rewardID").equals(id)) return true;
        return false;
    }

    static List<JSONObject> redemptionHistory(JSONObject state) {
        List<JSONObject> entries = rows(state, "redemptions");
        entries.addAll(rows(state, "fertilizations"));
        Collections.reverse(entries);
        entries.sort((a, b) -> Double.compare(b.optDouble("date"), a.optDouble("date")));
        return entries;
    }

    private static boolean unlockable(String id) {
        Item item = item(id);
        if (item != null && item.cost > 0) return true;
        for (Item reward : REWARDS) if (reward.id.equals(id) && reward.category.equals("Equip")) return true;
        return Arrays.asList("terracotta", "potBlue", "potPink", "potGold").contains(id);
    }

    private static void pruneRewards(JSONObject state) {
        List<JSONObject> history = redemptionHistory(state);
        if (history.size() <= HISTORY_LIMIT) return;
        List<JSONObject> excess = history.subList(HISTORY_LIMIT, history.size());
        Set<JSONObject> removed = new HashSet<>(excess);
        JSONArray unlocks = state.optJSONArray("olderUnlocks");
        if (unlocks == null) unlocks = new JSONArray();
        long spending = state.optLong("olderRewardSpending");
        for (JSONObject row : excess) {
            spending += row.optInt("cost");
            String id = row.optString("rewardID");
            if (unlockable(id) && !has(unlocks, id)) unlocks.put(id);
        }
        put(state, "olderRewardSpending", spending);
        put(state, "olderUnlocks", unlocks);
        for (String key : Arrays.asList("redemptions", "fertilizations")) {
            List<JSONObject> retained = rows(state, key);
            retained.removeIf(removed::contains);
            put(state, key, new JSONArray(retained));
        }
    }

    private static boolean migrateHistory(JSONObject state) {
        if (state.optInt("version") != 1) return false;
        pruneActivity(state);
        pruneRewards(state);
        put(state, "version", 2);
        return true;
    }

    static void redeem(JSONObject state, String id, String title, int cost, long now) {
        if (coins(state) < cost) throw new IllegalArgumentException();
        state.optJSONArray("redemptions").put(obj("id", uuid(), "rewardID", id, "title", title,
                "cost", cost, "date", date(now)));
        pruneRewards(state);
    }

    static void choose(JSONObject state, Item item, long now) {
        if (item.cost > 0 && !owned(state, item.id)) redeem(state, item.id, item.vi, item.cost, now);
        JSONObject focus = state.optJSONObject("focus");
        if (item.category.equals("Cây")) put(focus, "selectedPlant", item.id);
        else put(focus.optJSONObject("decorations"), item.category, item.id);
    }

    static void fertilize(JSONObject state, String id, int amount, long now) {
        JSONObject growth = state.optJSONObject("focus").optJSONObject("growth");
        if (amount <= 0 || amount > 25 || amount != Math.min(25, MAX_XP - points(growth, id))
                || (!id.equals("sprout") && !owned(state, id)) || coins(state) < amount * 2L) {
            throw new IllegalArgumentException();
        }
        state.optJSONArray("fertilizations").put(obj("id", uuid(), "plantID", id, "xp", amount,
                "cost", amount * 2, "date", date(now), "growthRevision", REVISION, "productID", "fertilizer-25-v1"));
        pruneRewards(state);
        nourish(growth, id, amount);
    }

    private static int points(JSONObject growth, String id) {
        JSONObject plant = growth.optJSONObject(id);
        return plant == null ? 0 : plant.optInt("points", plant.optInt("water") * 20 + plant.optInt("sunlight") * 2);
    }

    private static void nourish(JSONObject growth, String id, int amount) {
        int points = points(growth, id);
        put(growth, id, obj("water", 0, "sunlight", 0, "points",
                Math.max(points, Math.min(MAX_XP, points + amount))));
    }

    static int level(int xp) {
        int index = Arrays.binarySearch(LEVELS, xp);
        return index >= 0 ? index + 1 : Math.max(1, -index - 1);
    }

    private static int[] levels() {
        int[] thresholds = new int[100];
        int[] steps = new int[99];
        int span = 2 * MAX_XP / steps.length - 2;
        for (int i = 0; i < steps.length; i++) steps[i] = 1 + span * i / (steps.length - 1);
        int remainder = MAX_XP - Arrays.stream(steps).sum();
        for (int i = 0; i < steps.length; i++) {
            thresholds[i + 1] = thresholds[i] + steps[i] + (i >= steps.length - remainder ? 1 : 0);
        }
        return thresholds;
    }

    static boolean doneFocus(JSONObject session) {
        return session.optString("status").equals("done") && !session.optBoolean("isBreak");
    }

    int focusedToday(LocalDate day) {
        int minutes = 0;
        for (JSONObject row : rows(focus(), "sessions")) {
            if (doneFocus(row) && day(time(row, row.has("endedAt") ? "endedAt" : "ends")).equals(day)) {
                minutes += row.optInt("minutes");
            }
        }
        return minutes;
    }

    static void start(JSONObject state, int minutes, boolean rest, long now) {
        JSONObject focus = state.optJSONObject("focus");
        if (focus.optJSONObject("active") != null || minutes < (rest ? 5 : 10)
                || minutes > (rest ? 60 : 180) || (rest && minutes % 5 != 0)) throw new IllegalArgumentException();
        put(focus, "awaitingRest", false);
        if (!rest) put(focus, "preferredMinutes", minutes);
        put(focus, "active", obj("id", uuid(), "started", date(now), "ends", date(now + minutes * 60_000L),
                "minutes", minutes, "plantID", focus.optString("selectedPlant"), "strict", !rest,
                "isBreak", rest, "status", "running"));
        focus.remove("departure");
    }

    static String due(JSONObject focus, long now) {
        JSONObject session = focus.optJSONObject("active");
        if (session == null) return "";
        JSONObject departure = focus.optJSONObject("departure");
        long end = time(session, "ends");
        if (departure != null && !departure.has("lockedAt")) {
            long deadline = time(departure, "date") + GRACE;
            if (deadline < end && now >= deadline) return "interrupted";
        }
        return now >= end ? "done" : "";
    }

    static void finish(JSONObject state, long now, String status) {
        JSONObject focus = state.optJSONObject("focus");
        JSONObject session = focus.optJSONObject("active");
        if (session == null) return;
        put(session, "status", status);
        int minutes = session.optInt("minutes");
        boolean earned = doneFocus(session);
        put(session, "earnedXP", earned ? minutes : 0);
        long end = status.equals("done") ? time(session, "ends") : Math.max(now, time(session, "started"));
        put(session, "endedAt", date(end));
        put(session, "completedSeconds", Math.min(minutes * 60, (end - time(session, "started")) / 1000));
        focus.optJSONArray("sessions").put(session);
        focus.remove("active");
        focus.remove("departure");
        put(focus, "awaitingRest", earned);
        if (earned) nourish(focus.optJSONObject("growth"), session.optString("plantID"), minutes);
    }

    private static JSONObject initialFocus() {
        return obj("growthRevision", REVISION, "preferredMinutes", 25, "selectedPlant", "sprout",
                "growth", obj(), "sessions", new JSONArray(), "decorations", obj(), "awaitingRest", false);
    }

    private static JSONObject initial() {
        JSONArray habits = new JSONArray();
        habits.put(newHabit("Uống đủ nước", 6, "ly", "drop.fill", "blue"));
        habits.put(newHabit("Đọc 10 trang sách", 1, "lần", "book.closed.fill", "purple"));
        habits.put(newHabit("Vận động 15 phút", 1, "lần", "figure.walk", "orange"));
        return obj("version", 2, "habits", habits, "checkIns", new JSONArray(), "chests", new JSONArray(),
                "redemptions", new JSONArray(), "fertilizations", new JSONArray(), "customRewards", new JSONArray(),
                "equipped", "original", "petName", "Mầm", "reminderEnabled", false, "reminderHour", 20,
                "reminderMinute", 0, "focus", initialFocus());
    }

    static JSONObject newHabit(String title, int target, String unit, String symbol, String color) {
        return obj("id", uuid(), "title", title, "unit", unit, "symbol", symbol, "color", color,
                "target", target, "created", today().toString(), "archived", false,
                "weekdays", new JSONArray(Arrays.asList(1, 2, 3, 4, 5, 6, 7)));
    }

    private static JSONObject decode(byte[] bytes) throws JSONException {
        JSONObject state = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
        try {
            int version = state.optInt("version");
            require(version == 1 || version == 2);
            JSONObject focus = state.optJSONObject("focus");
            if (focus == null) {
                focus = initialFocus();
                put(state, "focus", focus);
            }
            if (state.isNull("fertilizations")) put(state, "fertilizations", new JSONArray());
            validate(state, focus);
            if (focus.optInt("growthRevision") < REVISION) {
                if (focus.optJSONObject("active") != null) finish(state, System.currentTimeMillis(), "cancelled");
                put(focus, "growth", obj());
                put(focus, "growthRevision", REVISION);
                put(focus, "awaitingRest", false);
                focus.remove("departure");
            }
            return state;
        } catch (RuntimeException e) {
            throw new JSONException("Invalid Focuz backup");
        }
    }

    private static void require(boolean valid) {
        if (!valid) throw new IllegalArgumentException();
    }

    private static List<JSONObject> checkedRows(JSONObject object, String key, int limit, boolean ids) {
        JSONArray array = object.optJSONArray(key);
        require(array != null && array.length() <= limit);
        List<JSONObject> list = rows(object, key);
        require(list.size() == array.length());
        if (ids) {
            Set<UUID> unique = new HashSet<>();
            for (JSONObject row : list) require(unique.add(UUID.fromString(row.optString("id"))));
        }
        return list;
    }

    static boolean validHabit(JSONObject habit) {
        JSONArray weekdays = habit.optJSONArray("weekdays");
        int target = habit.optInt("target");
        String title = habit.optString("title");
        if (title.trim().isEmpty() || title.length() > 70 || habit.optString("unit").length() > 20
                || target < 1 || target > 20 || weekdays == null || weekdays.length() < 1 || weekdays.length() > 7) return false;
        Set<Integer> days = new HashSet<>();
        for (int i = 0; i < weekdays.length(); i++) {
            int day = weekdays.optInt(i);
            if (day < 1 || day > 7 || !days.add(day)) return false;
        }
        JSONObject reminder = habit.optJSONObject("reminder");
        return reminder == null || validTime(reminder.optInt("hour", -1), reminder.optInt("minute", -1));
    }

    private static boolean validTime(int hour, int minute) { return hour >= 0 && hour < 24 && minute >= 0 && minute < 60; }

    private static void validate(JSONObject state, JSONObject focus) {
        Set<UUID> habitIds = new HashSet<>();
        for (JSONObject habit : checkedRows(state, "habits", 500, true)) {
            require(validHabit(habit));
            habitIds.add(UUID.fromString(habit.optString("id")));
            LocalDate.parse(habit.optString("created"));
        }
        Set<String> entries = new HashSet<>();
        for (JSONObject entry : checkedRows(state, "checkIns", 200_000, false)) {
            UUID id = UUID.fromString(entry.optString("habitID"));
            LocalDate day = LocalDate.parse(entry.optString("day"));
            int target = entry.optInt("target");
            int count = entry.optInt("count", -1);
            require(habitIds.contains(id) && entries.add(id + "|" + day) && target >= 1 && target <= 20
                    && count >= 0 && count <= target && (count != target || entry.optBoolean("rewarded")));
        }
        JSONArray chests = state.optJSONArray("chests");
        require(chests != null && chests.length() <= 200_000);
        Set<LocalDate> uniqueDays = new HashSet<>();
        for (int i = 0; i < chests.length(); i++) require(uniqueDays.add(LocalDate.parse(chests.optString(i))));
        for (JSONObject row : checkedRows(state, "redemptions", 100_000, true)) {
            require(row.optInt("cost") >= 10 && row.optInt("cost") <= 10_000 && row.has("date"));
        }
        for (JSONObject row : checkedRows(state, "customRewards", 500, true)) {
            require(!row.optString("title").trim().isEmpty() && row.optString("title").length() <= 70
                    && row.optInt("cost") >= 10 && row.optInt("cost") <= 10_000
                    && row.optBoolean("custom") && !row.optBoolean("decoration"));
        }
        for (JSONObject row : checkedRows(state, "fertilizations", 100_000, true)) {
            int xp = row.optInt("xp");
            require(xp >= 1 && xp <= 25 && row.optInt("cost") == xp * 2 && isPlant(row.optString("plantID"))
                    && row.optString("productID").equals("fertilizer-25-v1") && row.has("date"));
        }
        validateFocus(state, focus);
        long olderSpending = state.optLong("olderRewardSpending");
        require(olderSpending >= 0 && olderSpending <= coinsBeforeOlderSpending(state)
                && validTime(state.optInt("reminderHour", -1), state.optInt("reminderMinute", -1))
                && !state.optString("petName").isEmpty() && state.optString("petName").length() <= 24);
        if (!state.isNull("olderUnlocks")) {
            JSONArray unlocks = state.optJSONArray("olderUnlocks");
            require(unlocks != null);
            Set<String> unique = new HashSet<>();
            for (int i = 0; i < unlocks.length(); i++) {
                String id = unlocks.optString(i);
                require(unlockable(id) && unique.add(id));
            }
        }
        if (state.optInt("version") == 2) {
            require(recentActivity(state).size() <= HISTORY_LIMIT && redemptionHistory(state).size() <= HISTORY_LIMIT);
        }
    }

    private static void validateFocus(JSONObject state, JSONObject focus) {
        String plant = focus.optString("selectedPlant");
        int minutes = focus.optInt("preferredMinutes", 25);
        require(isPlant(plant) && (plant.equals("sprout") || owned(state, plant))
                && minutes >= 10 && minutes <= 180 && focus.optInt("growthRevision") <= REVISION);
        Set<String> sessions = new HashSet<>();
        for (JSONObject row : checkedRows(focus, "sessions", 100_000, true)) {
            sessions.add(row.optString("id").toUpperCase(java.util.Locale.ROOT));
            require(Arrays.asList("done", "cancelled", "interrupted").contains(row.optString("status")));
            validateSession(row);
        }
        JSONObject active = focus.optJSONObject("active");
        if (active != null) {
            validateSession(active);
            require(active.optString("status").equals("running") && !focus.optBoolean("awaitingRest")
                    && !sessions.contains(UUID.fromString(active.optString("id")).toString().toUpperCase(java.util.Locale.ROOT)));
        }
        JSONObject growth = focus.optJSONObject("growth");
        JSONObject decorations = focus.optJSONObject("decorations");
        require(growth != null && decorations != null);
        growth.keys().forEachRemaining(id -> require(isPlant(id) && growth.optJSONObject(id) != null
                && points(growth, id) >= 0 && points(growth, id) <= 1_000_000_000));
        for (String category : Arrays.asList("Nền", "Trang trí")) {
            if (!decorations.has(category)) continue;
            Item item = item(decorations.optString(category));
            require(item != null && item.category.equals(category) && owned(state, item.id));
        }
        JSONObject departure = focus.optJSONObject("departure");
        if (active == null && departure != null) focus.remove("departure");
        else if (departure != null) require(departure.optString("sessionID").equalsIgnoreCase(active.optString("id"))
                && time(departure, "date") >= time(active, "started") && time(departure, "date") < time(active, "ends"));
    }

    private static boolean isPlant(String id) {
        Item item = item(id);
        return item != null && item.category.equals("Cây");
    }

    private static void validateSession(JSONObject session) {
        int minutes = session.optInt("minutes");
        boolean rest = session.optBoolean("isBreak");
        require(isPlant(session.optString("plantID")) && minutes >= (rest ? 5 : 10) && minutes <= (rest ? 60 : 180)
                && (!rest || minutes % 5 == 0) && session.has("started") && session.has("ends")
                && Math.abs(time(session, "ends") - time(session, "started") - minutes * 60_000L) < 1_000);
    }
}
