#!/usr/bin/env bash
# Build APK Android MoveTrack AI. Dipakai GitHub Actions, bisa juga dijalankan
# di komputer yang sudah terpasang Flutter + Android SDK.
set -euo pipefail

LOG=ci-log.txt
: > "$LOG"

run() {
  echo "::group::$*"
  echo "\$ $*" >> "$LOG"
  "$@" 2>&1 | tee -a "$LOG"
  echo "::endgroup::"
}

flutter --version 2>&1 | tee -a "$LOG"

if [ ! -f android/app/src/main/AndroidManifest.xml ]; then
  run flutter create --org com.agus --project-name movetrack_ai --platforms android .
fi
run python3 ci/patch_android.py
run flutter pub get
run flutter analyze --no-fatal-infos --no-fatal-warnings
run flutter test

# Keystore tetap agar APK baru bisa dipasang menimpa versi lama.
mkdir -p "$HOME/.android"
cp ci/debug.keystore "$HOME/.android/debug.keystore"

run flutter build apk --release
echo "APK: build/app/outputs/flutter-apk/app-release.apk" | tee -a "$LOG"
