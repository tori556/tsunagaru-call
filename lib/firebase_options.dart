import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// このファイルは仮のスタブです。
/// ターミナルで `flutterfire configure` を実行すると、
/// あなたの Firebase プロジェクト用の設定で自動上書きされます。
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Firebase未設定のためデモモードで起動します。本番接続するには `flutterfire configure` を実行してください。',
    );
  }
}
