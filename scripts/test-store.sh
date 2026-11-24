#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/build/StoreTests.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$PROJECT_DIR/build/module-cache"
# UserNotifications requires an app bundle, even for an isolated command-line test.
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.focuz.storetests</string><key>CFBundleExecutable</key><string>StoreTests</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
swiftc -module-cache-path "$PROJECT_DIR/build/module-cache" -parse-as-library \
  "$PROJECT_DIR/MamHabit/Localization.swift" "$PROJECT_DIR/MamHabit/HabitEngine.swift" \
  "$PROJECT_DIR/MamHabit/SessionNotifications.swift" "$PROJECT_DIR/MamHabit/GardenStore.swift" "$PROJECT_DIR/Tests/StoreTests.swift" \
  -o "$APP_DIR/Contents/MacOS/StoreTests"
DATA_DIR="$(mktemp -d "$PROJECT_DIR/build/store-tests.XXXXXX")"
trap 'rm -rf "$DATA_DIR"' EXIT
"$APP_DIR/Contents/MacOS/StoreTests" "$DATA_DIR"
