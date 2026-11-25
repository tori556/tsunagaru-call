import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'screens/home_shell.dart';
import 'services/firebase_service.dart';
import 'services/push_callkit_incoming.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase未設定のためデモモード起動: $e');
  }

  await FirebaseService.instance.initialize(
    isFirebaseInitialized: firebaseReady,
  );

  await PushCallKitService.instance.initialize(
    firebaseReady: firebaseReady,
    onTokenUpdated: (token) {
      FirebaseService.instance.updateFcmToken(token);
    },
    onVoipTokenUpdated: (voipToken) {
      FirebaseService.instance.updateVoipToken(voipToken);
    },
  );

  runApp(const TsunagaruCallApp());
}

class TsunagaruCallApp extends StatelessWidget {
  const TsunagaruCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: FirebaseService.instance,
      builder: (context, _) {
        final largeFont = FirebaseService.instance.largeFont;
        return MaterialApp(
          title: 'つながる電話',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFF97316),
              surface: const Color(0xFFFFF9F2),
            ),
          ),
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(largeFont ? 1.18 : 1.0),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const HomeShell(),
        );
      },
    );
  }
}
