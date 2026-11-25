#!/usr/bin/env python3
"""Phase 4 Android 自動構成スクリプト:
- AndroidManifest.xml に必要権限とロック画面着信表示を追記
- build.gradle / build.gradle.kts の minSdk=24 / compileSdk=35 を自動設定
- 5カテゴリ分の着信音WAVを android/app/src/main/res/raw/ へ自動コピー
"""
import os
import re
import shutil

MANIFEST = "android/app/src/main/AndroidManifest.xml"
RAW_SRC = "assets/ringtones"
RAW_DST = "android/app/src/main/res/raw"

PERMS = """    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
    <uses-permission android:name="android.permission.VIBRATE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
"""

if os.path.exists(MANIFEST):
    txt = open(MANIFEST, encoding="utf-8").read()
    if "RECORD_AUDIO" not in txt:
        txt = txt.replace("<application", PERMS + "\n    <application", 1)
    if "android:showWhenLocked" not in txt and 'android:name=".MainActivity"' in txt:
        txt = txt.replace(
            'android:name=".MainActivity"',
            'android:name=".MainActivity"\n            android:showWhenLocked="true"\n            android:turnScreenOn="true"',
            1,
        )
    open(MANIFEST, "w", encoding="utf-8").write(txt)
    print("Patched:", MANIFEST)

GRADLE_FILES = [
    "android/app/build.gradle",
    "android/app/build.gradle.kts",
]
for gp in GRADLE_FILES:
    if os.path.exists(gp):
        gtxt = open(gp, encoding="utf-8").read()
        gtxt = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 24", gtxt)
        gtxt = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 24", gtxt)
        gtxt = re.sub(r"compileSdk\s*=\s*flutter\.compileSdkVersion", "compileSdk = 35", gtxt)
        gtxt = re.sub(r"compileSdkVersion\s+flutter\.compileSdkVersion", "compileSdkVersion 35", gtxt)
        gtxt = re.sub(r"targetSdk\s*=\s*flutter\.targetSdkVersion", "targetSdk = 34", gtxt)
        gtxt = re.sub(r"targetSdkVersion\s+flutter\.targetSdkVersion", "targetSdkVersion 34", gtxt)
        open(gp, "w", encoding="utf-8").write(gtxt)
        print("Patched Gradle SDK:", gp)

if os.path.isdir(RAW_SRC) and os.path.isdir("android/app/src/main/res"):
    os.makedirs(RAW_DST, exist_ok=True)
    for fn in sorted(os.listdir(RAW_SRC)):
        if fn.endswith(".wav"):
            shutil.copyfile(os.path.join(RAW_SRC, fn), os.path.join(RAW_DST, fn))
            print("Copied ringtone:", os.path.join(RAW_DST, fn))
