# つながる電話（Flutter × Firebase × LiveKit：Phase 4 完成版）本番公開チェックリスト

Phase 1〜4 までの全機能（LINE風4タブ・5カテゴリ連絡先・QR友だち追加・写真送信・グループトーク・グループ音声/ビデオ通話・iOS PushKit VoIP・TURN自動中継・カテゴリ別カスタム着信音）を搭載した最終構成です。

---

## Phase 4 で追加された最終仕上げ機能

1. **iOS PushKit 完全VoIP着信**
   - `native-config/ios/AppDelegate.swift`（`PKPushRegistryDelegate`）で、ロック画面・タスクキル状態からでも CallKit を即起動。
   - `firebase/functions/index.js` に外部パッケージ不要の **APNs HTTP/2 VoIP Push 送信（ES256 JWT）** を実装。
2. **TURN サーバー自動中継（4G/5G・厳格NAT対策）**
   - `firebase/functions/index.js` に `issueTurnCredentials`（coturn 時限クレデンシャル / 固定TURN両対応）を追加。
   - 通話画面上部にリアルタイムの回線品質ステータス（`🟢 接続良好 (TURN対応)` / `🟡 再接続中`）を表示。
3. **5カテゴリ別カスタム着信音＆試聴機能**
   - 家族・友達・仕事関係・親戚・その他それぞれのオリジナルWAV着信音5種を `assets/ringtones/` に同梱。
   - 「設定」→「カテゴリ別の着信音・バイブ設定」からプリセット選択・試聴・CallKit着信テストが可能。
4. **継続配信ワークフロー（Android APK / iOS TestFlight）**
   - `.github/workflows/build-flutter-apk.yml`（Debug / Release 切替対応）
   - `.github/workflows/build-ios-testflight.yml`（macOSランナーでの iOS ビルド＆PushKit自動適用）

---

## 本番公開チェックリスト

### 1. Firebase プロジェクト設定
- [ ] Firebase Console で **Authentication**（匿名 ＋ メール/パスワード）を有効化
- [ ] **Cloud Firestore** を作成し、`firebase/firestore.rules` を適用
- [ ] **Firebase Storage** を作成し、`firebase/storage.rules` を適用
- [ ] ターミナルで `flutterfire configure` を実行（`lib/firebase_options.dart` 生成）

### 2. Cloud Functions 環境変数（`firebase/functions/.env`）とデプロイ
```env
# グループ通話（LiveKit SFU）
LIVEKIT_API_KEY=your_livekit_key
LIVEKIT_API_SECRET=your_livekit_secret

# 携帯回線用 TURN サーバー（coturn または Metered / Cloudflare Calls）
TURN_URLS=turn:relay.example.com:3478,turns:relay.example.com:5349
TURN_AUTH_SECRET=your_coturn_static_auth_secret
# 固定認証方式を使う場合は TURN_AUTH_SECRET の代わりに以下を設定
# TURN_USERNAME=your_user
# TURN_CREDENTIAL=your_pass

# iOS PushKit 完全VoIP着信（Apple Developer の APNs .p8 認証キー）
APNS_KEY_ID=YOUR_10CHAR_KEY_ID
APNS_TEAM_ID=YOUR_10CHAR_TEAM_ID
APNS_BUNDLE_ID=jp.tsunagarucall.app
APNS_SANDBOX=false
APNS_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
```
```bash
cd firebase/functions && npm install && firebase deploy --only functions
```

### 3. Android APK / Play ストア配信準備
- [ ] `flutter create . --platforms=android --org jp.tsunagarucall`
- [ ] `python3 native-config/android/patch_manifest.py`（権限・ロック画面表示・5種の着信音WAVを `res/raw/` へ自動配置）
- [ ] `android/app/build.gradle` の `minSdk` を `23` 以上に設定
- [ ] `flutter build apk --release`（または GitHub Actions で自動生成）

### 4. iPhone TestFlight 配信準備（Mac + Xcode + Apple Developer）
- [ ] `flutter create . --platforms=ios --org jp.tsunagarucall`
- [ ] `native-config/ios/AppDelegate.swift` を `ios/Runner/AppDelegate.swift` へ上書き
- [ ] `native-config/ios/Info_追記用.plist` の内容を `ios/Runner/Info.plist` に追記
- [ ] `assets/ringtones/*.wav` を Xcode の `Runner` ターゲットへ追加（Copy Bundle Resources に含める）
- [ ] Xcode の **Signing & Capabilities** で `Push Notifications` と `Background Modes`（Audio / VoIP / Remote notifications / Background fetch）をON
- [ ] `flutter build ipa` → Xcode Organizer / Transporter で App Store Connect にアップロードし、TestFlight で家族・友人を招待
