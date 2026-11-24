#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  if [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  echo "Chưa có Xcode và iOS SDK. Cài Xcode, mở một lần để hoàn tất thiết lập, rồi chạy lại."
  exit 1
fi
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
xcodebuild -project "$PROJECT_DIR/MamHabit.xcodeproj" -scheme MamHabit \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$PROJECT_DIR/build" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
APP_DIR="$PROJECT_DIR/build/Build/Products/Release-iphoneos/MamHabit.app"
test -f "$APP_DIR/MamHabit"
file "$APP_DIR/MamHabit" | grep -q 'arm64'
xcrun vtool -show-build "$APP_DIR/MamHabit" | grep -Eq 'platform[[:space:]]+IOS$'
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT
mkdir -p "$STAGING_DIR/Payload"
cp -R "$APP_DIR" "$STAGING_DIR/Payload/MamHabit.app"
rm -rf "$STAGING_DIR/Payload/MamHabit.app/_CodeSignature"
rm -f "$STAGING_DIR/Payload/MamHabit.app/embedded.mobileprovision"
(cd "$STAGING_DIR" && /usr/bin/zip -qry "$OUTPUT_DIR/Focuz-unsigned.ipa" Payload)
unzip -t "$OUTPUT_DIR/Focuz-unsigned.ipa"
echo "Đã xuất: $OUTPUT_DIR/Focuz-unsigned.ipa"
echo "Đây là IPA chưa ký; dùng Sideloadly hoặc AltStore Classic để ký và cài lên iPhone."
