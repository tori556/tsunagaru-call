#!/usr/bin/env python3
import base64
import json
import os
import re
from pathlib import Path
from xml.sax.saxutils import escape as xml_escape

manifest_path = Path("android/app/src/main/AndroidManifest.xml")

# Android プロジェクト本体が生成される前に android/ フォルダを先に作らない
if not manifest_path.exists():
    print("[info] AndroidManifest.xml not found yet; deferring Android config until after flutter create.")
    raise SystemExit(0)

# 1. AndroidManifest.xml の v2 embedding 保護 ＋ TimeTree / LINE / ブラウザ / 電話 の起動許可を補完
man_txt = manifest_path.read_text(encoding="utf-8", errors="ignore")
man_orig = man_txt

if 'android:name="flutterEmbedding"' not in man_txt and "</application>" in man_txt:
    v2_meta = '        <meta-data android:name="flutterEmbedding" android:value="2" />\n'
    man_txt = man_txt.replace("</application>", v2_meta + "    </application>", 1)
    print("[updated] Added flutterEmbedding v2 metadata")

needed_schemes = ["https", "http", "tel", "timetree", "line"]
missing_intents = []
for sc in needed_schemes:
    if f'android:scheme="{sc}"' not in man_txt:
        missing_intents.append(
            f'        <intent>\n'
            f'            <action android:name="android.intent.action.VIEW" />\n'
            f'            <data android:scheme="{sc}" />\n'
            f'        </intent>\n'
        )
if missing_intents:
    joined_intents = "".join(missing_intents)
    if "</queries>" in man_txt:
        man_txt = man_txt.replace("</queries>", joined_intents + "    </queries>", 1)
    elif "</manifest>" in man_txt:
        man_txt = man_txt.replace(
            "</manifest>",
            f"    <queries>\n{joined_intents}    </queries>\n</manifest>",
            1,
        )
    print("[updated] Added queries intents for external apps (https/http/tel/timetree/line)")

if man_txt != man_orig:
    manifest_path.write_text(man_txt, encoding="utf-8")

# 2. GOOGLE_SERVICES_JSON_B64 から google-services.json と res/values/firebase_options.xml を直接生成
secret_val = os.environ.get("GOOGLE_SERVICES_JSON_B64", "").strip()
if not secret_val:
    print("[warn] GOOGLE_SERVICES_JSON_B64 is empty; skipping Firebase resource generation.")
    raise SystemExit(0)

if secret_val.startswith("{"):
    raw = secret_val.encode("utf-8")
else:
    raw = base64.b64decode("".join(secret_val.split()))

data = json.loads(raw.decode("utf-8"))

project_info = data.get("project_info", {}) or {}
clients = data.get("client", []) or []
if not clients:
    raise SystemExit("[error] google-services.json に client 情報が含まれていません")

chosen = clients[0]
for c in clients:
    pn = (c.get("client_info", {}) or {}).get("android_client_info", {}).get("package_name", "")
    if pn == "jp.tsunagarucall.tsunagaru_call":
        chosen = c
        break

client_info = chosen.get("client_info", {}) or {}
pkg_name = (client_info.get("android_client_info", {}) or {}).get("package_name", "")
app_id = client_info.get("mobilesdk_app_id", "")
api_keys = chosen.get("api_key", []) or []
api_key = (api_keys[0] or {}).get("current_key", "") if api_keys else ""
project_id = project_info.get("project_id", "")
project_number = project_info.get("project_number", "")
storage_bucket = project_info.get("storage_bucket", "")
firebase_url = project_info.get("firebase_url", "")

default_web_client_id = ""
for oc in chosen.get("oauth_client", []) or []:
    if oc.get("client_type") == 3 and oc.get("client_id"):
        default_web_client_id = oc["client_id"]
        break

if not app_id or not api_key or not project_id:
    raise SystemExit(
        f"[error] google-services.json 必須項目不足: app_id={bool(app_id)}, api_key={bool(api_key)}, project_id={bool(project_id)}"
    )

out_json = Path("android/app/google-services.json")
out_json.parent.mkdir(parents=True, exist_ok=True)
out_json.write_bytes(raw)

res_entries = [
    ("google_app_id", app_id),
    ("google_api_key", api_key),
    ("google_crash_reporting_api_key", api_key),
    ("gcm_defaultSenderId", project_number),
    ("project_id", project_id),
    ("google_storage_bucket", storage_bucket),
    ("firebase_database_url", firebase_url),
    ("default_web_client_id", default_web_client_id),
]

xml_lines = ['<?xml version="1.0" encoding="utf-8"?>', "<resources>"]
for key, val in res_entries:
    if val:
        xml_lines.append(
            f'    <string name="{key}" translatable="false">{xml_escape(str(val))}</string>'
        )
xml_lines.append("</resources>")
xml_lines.append("")

res_xml_path = Path("android/app/src/main/res/values/firebase_options.xml")
res_xml_path.parent.mkdir(parents=True, exist_ok=True)
res_xml_path.write_text("\n".join(xml_lines), encoding="utf-8")
print(f"[ok] Generated {res_xml_path} (project_id={project_id}, package_name={pkg_name})")

# 重複リソース衝突を防ぐため、Gradle 側の google-services プラグイン行を除去し applicationId を一致させる
for gradle_file in [
    Path("android/settings.gradle.kts"),
    Path("android/settings.gradle"),
    Path("android/build.gradle.kts"),
    Path("android/build.gradle"),
    Path("android/app/build.gradle.kts"),
    Path("android/app/build.gradle"),
]:
    if not gradle_file.exists():
        continue
    gtxt = gradle_file.read_text(encoding="utf-8", errors="ignore")
    gorig = gtxt
    gtxt = re.sub(r'^.*com\.google\.gms[\.:]google-services.*\n?', '', gtxt, flags=re.M)
    if gradle_file.name.startswith("build.gradle") and gradle_file.parent.name == "app" and pkg_name:
        if gradle_file.name.endswith(".kts"):
            gtxt = re.sub(r'applicationId\s*=\s*"[^"]+"', f'applicationId = "{pkg_name}"', gtxt, count=1)
        else:
            gtxt = re.sub(r'applicationId\s*=?\s*["\'][^"\']+["\']', f'applicationId "{pkg_name}"', gtxt, count=1)
    if gtxt != gorig:
        gradle_file.write_text(gtxt, encoding="utf-8")
        print(f"[updated] {gradle_file}")

# 3. AndroidManifest.xml に INTERNET 権限を保証 & R8 コード圧縮を無効化（Firestore unavailable 防止）
man_now = manifest_path.read_text(encoding="utf-8", errors="ignore")
if "android.permission.INTERNET" not in man_now and "<application" in man_now:
    man_now = man_now.replace(
        "<application",
        '    <uses-permission android:name="android.permission.INTERNET" />
    <application',
        1,
    )
    manifest_path.write_text(man_now, encoding="utf-8")
    print("[updated] Added INTERNET permission to AndroidManifest.xml")

app_kts = Path("android/app/build.gradle.kts")
app_groovy = Path("android/app/build.gradle")
if app_kts.exists():
    atxt = app_kts.read_text(encoding="utf-8", errors="ignore")
    if "isMinifyEnabled = false" not in atxt:
        atxt = re.sub(
            r'(getByName\("release"\)\s*\{|release\s*\{)',
            r'\1
            isMinifyEnabled = false
            isShrinkResources = false',
            atxt,
            count=1,
        )
        app_kts.write_text(atxt, encoding="utf-8")
        print("[updated] Disabled R8 minify/shrink in android/app/build.gradle.kts")
elif app_groovy.exists():
    atxt = app_groovy.read_text(encoding="utf-8", errors="ignore")
    if "minifyEnabled false" not in atxt:
        atxt = re.sub(
            r'(release\s*\{)',
            r'\1
            minifyEnabled false
            shrinkResources false',
            atxt,
            count=1,
        )
        app_groovy.write_text(atxt, encoding="utf-8")
        print("[updated] Disabled R8 minify/shrink in android/app/build.gradle")
