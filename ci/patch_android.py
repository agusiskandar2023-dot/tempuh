#!/usr/bin/env python3
"""Menambahkan konfigurasi Android yang dibutuhkan MoveTrack AI ke folder
android/ hasil `flutter create`:
- izin lokasi, foreground service (lokasi), wake lock, notifikasi, baterai
- izin & intent Health Connect (untuk data Garmin)
- MainActivity -> FlutterFragmentActivity (wajib untuk plugin health)
- minSdk 26 (Health Connect)
Skrip ini idempoten: aman dijalankan berulang.
"""
import glob
import re
import sys

MANIFEST = "android/app/src/main/AndroidManifest.xml"

PERMISSIONS = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_LOCATION",
    "android.permission.WAKE_LOCK",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
    "android.permission.health.READ_EXERCISE",
    "android.permission.health.READ_HEART_RATE",
    "android.permission.health.READ_DISTANCE",
    "android.permission.health.READ_TOTAL_CALORIES_BURNED",
    "android.permission.health.READ_ACTIVE_CALORIES_BURNED",
    "android.permission.health.READ_STEPS",
]

QUERIES = """    <queries>
        <package android:name="com.google.android.apps.healthdata" />
        <intent>
            <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />
        </intent>
    </queries>
"""

RATIONALE_FILTER = """            <intent-filter>
                <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />
            </intent-filter>
"""

ALIAS = """        <activity-alias
            android:name="ViewPermissionUsageActivity"
            android:exported="true"
            android:targetActivity=".MainActivity"
            android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
            <intent-filter>
                <action android:name="android.intent.action.VIEW_PERMISSION_USAGE" />
                <category android:name="android.intent.category.HEALTH_PERMISSIONS" />
            </intent-filter>
        </activity-alias>
"""


def patch_manifest():
    with open(MANIFEST, encoding="utf-8") as f:
        xml = f.read()

    perms = "".join(
        f'    <uses-permission android:name="{p}" />\n'
        for p in PERMISSIONS
        if f'android:name="{p}"' not in xml
    )
    if perms:
        xml = re.sub(r"(<manifest[^>]*>\n)", lambda m: m.group(1) + perms, xml, count=1)

    if "com.google.android.apps.healthdata" not in xml:
        if "<queries>" in xml:
            xml = xml.replace(
                "<queries>",
                '<queries>\n        <package android:name="com.google.android.apps.healthdata" />\n'
                '        <intent>\n            <action android:name="androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE" />\n        </intent>',
                1,
            )
        else:
            xml = xml.replace("</manifest>", QUERIES + "</manifest>", 1)

    if 'android:label="movetrack_ai"' in xml:
        xml = xml.replace('android:label="movetrack_ai"', 'android:label="MoveTrack AI"')

    if "ACTION_SHOW_PERMISSIONS_RATIONALE\" />\n            </intent-filter>" not in xml:
        # sisipkan intent-filter rationale ke dalam <activity ... .MainActivity>
        idx = xml.find('android:name=".MainActivity"')
        if idx < 0:
            sys.exit("MainActivity tidak ditemukan di manifest")
        end = xml.find("</activity>", idx)
        xml = xml[:end] + RATIONALE_FILTER + "        " + xml[end:]

    if "ViewPermissionUsageActivity" not in xml:
        xml = xml.replace("</application>", ALIAS + "    </application>", 1)

    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write(xml)


def patch_main_activity():
    files = glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True)
    if not files:
        sys.exit("MainActivity.kt tidak ditemukan")
    for path in files:
        with open(path, encoding="utf-8") as f:
            src = f.read()
        src = src.replace(
            "import io.flutter.embedding.android.FlutterActivity",
            "import io.flutter.embedding.android.FlutterFragmentActivity",
        )
        src = re.sub(r":\s*FlutterActivity\(\)", ": FlutterFragmentActivity()", src)
        with open(path, "w", encoding="utf-8") as f:
            f.write(src)


def patch_gradle():
    paths = glob.glob("android/app/build.gradle.kts") + glob.glob("android/app/build.gradle")
    if not paths:
        sys.exit("build.gradle app tidak ditemukan")
    for path in paths:
        with open(path, encoding="utf-8") as f:
            g = f.read()
        if path.endswith(".kts"):
            g = re.sub(r"minSdk\s*=\s*[^\n]+", "minSdk = 26", g)
        else:
            g = re.sub(r"minSdkVersion\s+[^\n]+", "minSdkVersion 26", g)
            g = re.sub(r"minSdk\s*=\s*[^\n]+", "minSdk = 26", g)
        with open(path, "w", encoding="utf-8") as f:
            f.write(g)


if __name__ == "__main__":
    patch_manifest()
    patch_main_activity()
    patch_gradle()
    print("Android patched.")
