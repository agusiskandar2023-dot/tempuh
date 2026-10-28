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

# Pastikan APK ditandatangani dengan kunci Tempuh yang tetap. Kalau berbeda,
# Android menolak update ("App not installed"), jadi build dihentikan.
EXPECTED_CERT=804fb5c8d55d4696ee8a3d32b6baa3e1f7d9188f8e1a86b92a3262b7fe4b14f0
APKSIGNER=$(ls -d "${ANDROID_HOME:-$ANDROID_SDK_ROOT}"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)
ACTUAL_CERT=$("$APKSIGNER" verify --print-certs build/app/outputs/flutter-apk/app-release.apk \
  | grep -m1 'certificate SHA-256 digest' | awk '{print $NF}')
echo "Signing cert: $ACTUAL_CERT" | tee -a "$LOG"
if [ "$ACTUAL_CERT" != "$EXPECTED_CERT" ]; then
  echo "ERROR: APK tidak ditandatangani dengan kunci Tempuh (ci/debug.keystore)" | tee -a "$LOG"
  exit 1
fi
echo "APK: build/app/outputs/flutter-apk/app-release.apk" | tee -a "$LOG"
