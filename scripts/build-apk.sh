#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Library/Android/sdk}}"
tools="$sdk/build-tools/35.0.0"
platform="$sdk/platforms/android-35/android.jar"
java_bin="${JAVA_HOME:+$JAVA_HOME/bin/}"
signing="${FOCUZ_ANDROID_SIGNING_DIR:-$root/build/android-signing}"
out="${FOCUZ_ANDROID_OUTPUT_DIR:-$root/dist}"

if [[ ! -f "$platform" || ! -x "$tools/aapt2" ]] || ! "${java_bin}javac" -version; then
    echo "Android SDK Platform 35, Build Tools 35.0.0 and JDK 17 are required." >&2
    exit 1
fi
if [[ -n "${JAVA_HOME:-}" ]]; then export JAVA_HOME; fi

work="$(mktemp -d "${TMPDIR:-/tmp}/focuz-apk.XXXXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/classes" "$work/dex" "$work/assets/art" "$work/res/drawable-nodpi" "$work/res/raw" "$out"
cp -R "$root/android/res/." "$work/res/"
for source in "$root"/MamHabit/Assets.xcassets/*.imageset/art.*; do
    name="$(basename "$(dirname "$source")" .imageset)"
    cp "$source" "$work/assets/art/$name.${source##*.}"
done
cp "$root/MamHabit/Assets.xcassets/AppIcon.appiconset/AppIcon.png" "$work/res/drawable-nodpi/focuz.png"
cp "$root/MamHabit/Sounds/giot-nang.wav" "$work/res/raw/giot_nang.wav"

"$tools/aapt2" compile --dir "$work/res" -o "$work/resources.zip"
"$tools/aapt2" link -I "$platform" --manifest "$root/android/AndroidManifest.xml" \
    -A "$work/assets" --java "$work" -o "$work/base.apk" "$work/resources.zip"
"${java_bin}javac" --release 8 -encoding UTF-8 -classpath "$platform" -d "$work/classes" \
    "$root"/android/src/com/mamhabit/personal/*.java "$work/com/mamhabit/personal/R.java"
"${java_bin}jar" cf "$work/classes.jar" -C "$work/classes" .
"$tools/d8" --release --min-api 26 --lib "$platform" --output "$work/dex" "$work/classes.jar"
(cd "$work/dex" && zip -q "$work/base.apk" classes*.dex)
"$tools/zipalign" -p -f 4 "$work/base.apk" "$work/aligned.apk"

# Keep the signing identity for subsequent sideload updates. Back it up privately.
(
    umask 077
    mkdir -p "$signing"
    if [[ ! -s "$signing/password" && ! -e "$signing/focuz.p12" ]]; then
        openssl rand -hex 32 > "$signing/password"
    fi
    if [[ ! -s "$signing/focuz.p12" ]]; then
        "${java_bin}keytool" -genkeypair -keystore "$signing/focuz.p12" -storetype PKCS12 \
            -storepass:file "$signing/password" -alias focuz -keyalg RSA -keysize 3072 \
            -validity 10000 -dname 'CN=Focuz Android' -noprompt
    fi
)
"$tools/apksigner" sign --ks "$signing/focuz.p12" --ks-key-alias focuz \
    --ks-pass "file:$signing/password" --out "$work/signed.apk" "$work/aligned.apk"
"$tools/apksigner" verify --verbose "$work/signed.apk"
version="$(sed -nE 's/.*android:versionName="([^"]+)".*/\1/p' "$root/android/AndroidManifest.xml" | tr -d '\r')"
mv "$work/signed.apk" "$out/Focuz-$version-Android.apk"
echo "$out/Focuz-$version-Android.apk"
