#!/usr/bin/env python3
import base64
import json
import os
import re
from pathlib import Path

manifest_path = Path("android/app/src/main/AndroidManifest.xml")

# Android プロジェクト本体が生成される前に android/ フォルダを先に作らない
if not manifest_path.exists():
    print("[info] AndroidManifest.xml not found yet; deferring Firebase config until after flutter create.")
    raise SystemExit(0)

# Android v2 embedding メタデータが欠けていれば補完
man_txt = manifest_path.read_text(encoding="utf-8", errors="ignore")
if 'android:name="flutterEmbedding"' not in man_txt and "</application>" in man_txt:
    v2_meta = '        <meta-data android:name="flutterEmbedding" android:value="2" />\n'
    man_txt = man_txt.replace("</application>", v2_meta + "    </application>", 1)
    manifest_path.write_text(man_txt, encoding="utf-8")
    print("[updated] Added flutterEmbedding v2 metadata to AndroidManifest.xml")

secret_val = os.environ.get("GOOGLE_SERVICES_JSON_B64", "").strip()
if not secret_val:
    print("[info] GOOGLE_SERVICES_JSON_B64 is not set; building in local mode.")
    raise SystemExit(0)

if secret_val.startswith("{"):
    raw = secret_val.encode("utf-8")
else:
    raw = base64.b64decode("".join(secret_val.split()))

data = json.loads(raw.decode("utf-8"))

pkg_name = ""
for client in data.get("client", []):
    pn = client.get("client_info", {}).get("android_client_info", {}).get("package_name", "")
    if pn:
        pkg_name = pn
        break

out_path = Path("android/app/google-services.json")
out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_bytes(raw)
print(f"[ok] Wrote {out_path} (package_name={pkg_name or 'unknown'})")

def insert_into_plugins_block(text: str, plugin_line: str) -> str:
    m = re.search(r"plugins\s*\{", text)
    if not m:
        return text
    depth = 0
    for idx in range(m.end() - 1, len(text)):
        ch = text[idx]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[:idx] + f"    {plugin_line}\n" + text[idx:]
    return text

settings_kts = Path("android/settings.gradle.kts")
settings_groovy = Path("android/settings.gradle")
declared_in_settings = False

if settings_kts.exists():
    stxt = settings_kts.read_text(encoding="utf-8", errors="ignore")
    if "com.google.gms.google-services" not in stxt:
        stxt_new = insert_into_plugins_block(
            stxt,
            'id("com.google.gms.google-services") version "4.4.2" apply false',
        )
        if stxt_new != stxt:
            settings_kts.write_text(stxt_new, encoding="utf-8")
            print("[updated] android/settings.gradle.kts")
            declared_in_settings = True
    else:
        declared_in_settings = True
elif settings_groovy.exists():
    stxt = settings_groovy.read_text(encoding="utf-8", errors="ignore")
    if "com.google.gms.google-services" in stxt:
        declared_in_settings = True
    elif "plugins {" in stxt:
        stxt_new = insert_into_plugins_block(
            stxt,
            'id "com.google.gms.google-services" version "4.4.2" apply false',
        )
        if stxt_new != stxt:
            settings_groovy.write_text(stxt_new, encoding="utf-8")
            print("[updated] android/settings.gradle")
            declared_in_settings = True

root_groovy = Path("android/build.gradle")
if root_groovy.exists() and not declared_in_settings:
    rtxt = root_groovy.read_text(encoding="utf-8", errors="ignore")
    if "com.google.gms:google-services" not in rtxt and "dependencies {" in rtxt:
        rtxt_new = re.sub(
            r"(dependencies\s*\{)",
            r"\1\n        classpath 'com.google.gms:google-services:4.4.2'",
            rtxt,
            count=1,
        )
        if rtxt_new != rtxt:
            root_groovy.write_text(rtxt_new, encoding="utf-8")
            print("[updated] android/build.gradle")

app_kts = Path("android/app/build.gradle.kts")
app_groovy = Path("android/app/build.gradle")

if app_kts.exists():
    atxt = app_kts.read_text(encoding="utf-8", errors="ignore")
    orig = atxt
    if "com.google.gms.google-services" not in atxt:
        atxt = insert_into_plugins_block(atxt, 'id("com.google.gms.google-services")')
    if pkg_name:
        atxt = re.sub(
            r'applicationId\s*=\s*"[^"]+"',
            f'applicationId = "{pkg_name}"',
            atxt,
            count=1,
        )
    if atxt != orig:
        app_kts.write_text(atxt, encoding="utf-8")
        print("[updated] android/app/build.gradle.kts")
elif app_groovy.exists():
    atxt = app_groovy.read_text(encoding="utf-8", errors="ignore")
    orig = atxt
    if "com.google.gms.google-services" not in atxt:
        if "plugins {" in atxt:
            atxt = insert_into_plugins_block(atxt, 'id "com.google.gms.google-services"')
        else:
            atxt = atxt.rstrip() + "\napply plugin: 'com.google.gms.google-services'\n"
    if pkg_name:
        atxt = re.sub(
            r'applicationId\s*=?\s*["\'][^"\']+["\']',
            f'applicationId "{pkg_name}"',
            atxt,
            count=1,
        )
    if atxt != orig:
        app_groovy.write_text(atxt, encoding="utf-8")
        print("[updated] android/app/build.gradle")
