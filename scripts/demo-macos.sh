#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_DIR="$PROJECT_DIR/build/demo"
APP_DIR="$DEMO_DIR/Focuz Demo.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/Artwork" "$PROJECT_DIR/build/module-cache"
swiftc -module-cache-path "$PROJECT_DIR/build/module-cache" -parse-as-library "$PROJECT_DIR"/MamHabit/*.swift -o "$APP_DIR/Contents/MacOS/Focuz"
cp -R "$PROJECT_DIR"/MamHabit/Assets.xcassets/*.imageset "$APP_DIR/Contents/Resources/Artwork/"
cp "$PROJECT_DIR"/MamHabit/Sounds/*.wav "$APP_DIR/Contents/Resources/"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.focuz.localdemo</string>
<key>CFBundleName</key><string>Focuz Demo</string>
<key>CFBundleDisplayName</key><string>Focuz Demo</string>
<key>CFBundleExecutable</key><string>Focuz</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
python3 - "$PROJECT_DIR/MamHabit.xcodeproj/project.pbxproj" "$APP_DIR/Contents/Info.plist" <<'PY'
import pathlib, plistlib, re, sys
source = pathlib.Path(sys.argv[1]).read_text()
path = pathlib.Path(sys.argv[2])
info = plistlib.loads(path.read_bytes())
info["CFBundleShortVersionString"] = re.search(r"MARKETING_VERSION = ([\d.]+);", source)[1]
info["CFBundleVersion"] = re.search(r"CURRENT_PROJECT_VERSION = (\d+);", source)[1]
path.write_bytes(plistlib.dumps(info))
PY
# This preview never reads or writes the user's real Focuz app data.
if [ "${1:-}" = "--build-only" ]; then echo "Built: $APP_DIR"; exit 0; fi
export FOCUZ_DEMO_STATE="$DEMO_DIR/state.json"
exec "$APP_DIR/Contents/MacOS/Focuz"
