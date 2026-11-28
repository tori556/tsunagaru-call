import 'dart:async';
import 'dart:convert';
import 'dart:math';
 
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';
 
import '../models.dart';
 
class ErrorGuard {
  static final ValueNotifier<List<String>> logs = ValueNotifier<List<String>>(
    const <String>[],
  );
 
  static void record(String message, [StackTrace? stack]) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final entry = '[$ts] $message';
    debugPrint(entry);
    if (stack != null) debugPrint(stack.toString());
    final next = <String>[entry, ...logs.value];
    if (next.length > 40) next.removeRange(40, next.length);
    logs.value = next;
  }
 
  static void clear() => logs.value = const <String>[];
}
 
class SafeRunner {
  static Future<T> runWithRetry<T>({
    required Future<T> Function(int attempt) task,
    int maxAttempts = 3,
    Duration initialDelay = const Duration(milliseconds: 400),
    void Function(int attempt, dynamic error)? onRetry,
  }) async {
    var delay = initialDelay;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await task(attempt);
      } catch (error, stack) {
        ErrorGuard.record('自動リトライ ($attempt/$maxAttempts): $error', stack);
        if (attempt >= maxAttempts) rethrow;
        onRetry?.call(attempt, error);
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }
    throw StateError('Retry finished unexpectedly');
  }
}
 
class NetworkGuard {
  static bool isWifiOrEthernet(List<ConnectivityResult> results) {
    return results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
  }
 
  static bool isOffline(List<ConnectivityResult> results) {
    return results.isEmpty ||
        results.every((r) => r == ConnectivityResult.none);
  }
 
  static String describe(List<ConnectivityResult> results) {
    if (isOffline(results)) return 'オフライン（通信なし）';
    if (results.contains(ConnectivityResult.wifi)) return 'Wi-Fi 接続中';
    if (results.contains(ConnectivityResult.ethernet)) return '有線LAN 接続中';
    if (results.contains(ConnectivityResult.mobile)) return 'モバイル通信（Wi-Fi外）';
    return 'その他の回線（Wi-Fi外）';
  }
 
  static Future<bool> confirmIfNotWifi(
    BuildContext context, {
    required String actionName,
    required bool warnOnNonWifi,
    int? fileSizeBytes,
  }) async {
    List<ConnectivityResult> results;
    try {
      results = await Connectivity().checkConnectivity();
    } catch (e, s) {
      ErrorGuard.record('回線確認エラー（続行）: $e', s);
      return true;
    }
    if (!context.mounted) return false;
 
    if (isOffline(results)) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext dc) => AlertDialog(
          icon: const Icon(Icons.wifi_off, color: Colors.redAccent, size: 32),
          title: const Text('インターネット未接続'),
          content: Text('オフラインのため「$actionName」を実行できません。'),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dc).pop(),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
      return false;
    }
 
    if (isWifiOrEthernet(results) || !warnOnNonWifi) return true;
 
    final sizeNote = (fileSizeBytes != null && fileSizeBytes > 0)
        ? '\n対象サイズ: ${formatBytes(fileSizeBytes)}'
        : '';
 
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dc) => AlertDialog(
        icon: const Icon(Icons.signal_cellular_alt, color: Colors.orange, size: 32),
        title: const Text('Wi-Fi に接続されていません'),
        content: Text(
          '現在はモバイル回線（Wi-Fi外）です。$sizeNote\n'
          '「$actionName」を続けるとデータ通信量を消費します。\n\nこのまま続けますか？',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dc).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dc).pop(true),
            child: const Text('このまま続ける'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}
 
class ExternalAppLauncher {
  static Future<void> openTimeTree(BuildContext context) => _launch(
        context,
        name: 'TimeTree',
        primary: Uri.parse('timetree://'),
        fallback: Uri.parse('https://timetreeapp.com/'),
      );
 
  static Future<void> openLine(BuildContext context) => _launch(
        context,
        name: 'LINE',
        primary: Uri.parse('line://'),
        fallback: Uri.parse('https://line.me/'),
      );
 
  static Future<void> openUrl(BuildContext context, String url) => _launch(
        context,
        name: 'リンク',
        primary: Uri.parse(url),
        fallback: Uri.parse(url),
      );
 
  static Future<void> _launch(
    BuildContext context, {
    required String name,
    required Uri primary,
    required Uri fallback,
  }) async {
    try {
      final opened = await SafeRunner.runWithRetry<bool>(
        maxAttempts: 2,
        task: (_) async {
          if (await launchUrl(primary, mode: LaunchMode.externalApplication)) {
            return true;
          }
          return launchUrl(fallback, mode: LaunchMode.externalApplication);
        },
      );
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name を開けませんでした。')),
        );
      }
    } catch (e, s) {
      ErrorGuard.record('$name 起動エラー: $e', s);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name の起動に失敗しましたが安全に動作中です。')),
        );
      }
    }
  }
}
 
class UpdateChecker {
  static int get currentBuildNumber => int.tryParse(appBuildNumberStr) ?? 1;
 
  static Future<UpdateInfo?> checkLatest() async {
    if (githubRepo.isEmpty) return null;
    final url =
        'https://github.com/$githubRepo/releases/download/latest-android/version.json';
    return SafeRunner.runWithRetry<UpdateInfo?>(
      maxAttempts: 2,
      task: (_) async {
        final res =
            await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) return null;
        final map = jsonDecode(utf8.decode(res.bodyBytes)) as JsonMap;
        final remoteBuild = (map['buildNumber'] as num?)?.toInt() ?? 0;
        if (remoteBuild <= currentBuildNumber) return null;
        return UpdateInfo(
          buildNumber: remoteBuild,
          versionName: (map['versionName'] as String?) ?? '1.0.$remoteBuild',
          notes: (map['notes'] as String?) ?? '最新版が公開されています。',
          apkUrl: (map['apkUrl'] as String?) ??
              'https://github.com/$githubRepo/releases/download/latest-android/tsunagaru-latest.apk',
        );
      },
    );
  }
}
 
class AuthLockService {
  static const FlutterSecureStorage _secure = FlutterSecureStorage();
  static const String _pinHashKey = 'tsunagaru_pin_hash_v2';
  static const String _pinSaltKey = 'tsunagaru_pin_salt_v2';
  static final LocalAuthentication _localAuth = LocalAuthentication();
 
  static Future<String> _getOrCreateSalt() async {
    final existing = await _secure.read(key: _pinSaltKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    final salt = base64UrlEncode(bytes);
    await _secure.write(key: _pinSaltKey, value: salt);
    return salt;
  }
 
  static String _hashPin(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt::$pin')).toString();
 
  static Future<void> savePin(String pin) async {
    final salt = await _getOrCreateSalt();
    await _secure.write(key: _pinHashKey, value: _hashPin(salt, pin));
  }
 
  static Future<bool> hasPin() async {
    try {
      final v = await _secure.read(key: _pinHashKey);
      return v != null && v.isNotEmpty;
    } catch (e, s) {
      ErrorGuard.record('PIN確認エラー: $e', s);
      return false;
    }
  }
 
  static Future<bool> verifyPin(String pin) async {
    try {
      final saved = await _secure.read(key: _pinHashKey);
      if (saved == null || saved.isEmpty) return true;
      final salt = await _getOrCreateSalt();
      return saved == _hashPin(salt, pin);
    } catch (e, s) {
      ErrorGuard.record('PIN照合エラー: $e', s);
      return false;
    }
  }
 
  static Future<void> clearPin() async {
    try {
      await _secure.delete(key: _pinHashKey);
      await _secure.delete(key: _pinSaltKey);
    } catch (e, s) {
      ErrorGuard.record('PIN消去エラー: $e', s);
    }
  }
 
  static Future<bool> canUseBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }
 
  static Future<bool> authenticateBiometric() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'tranceferのロックを解除します',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (e, s) {
      ErrorGuard.record('生体認証キャンセル/失敗: $e', s);
      return false;
    }
  }
}
