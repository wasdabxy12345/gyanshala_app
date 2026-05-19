import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/auth/presentation/screens/signup_verification_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'firebase_options.dart';

const _supabaseUrl = 'https://ntrniclejneisdzepntv.supabase.co';
const _supabaseAnonKey = 'sb_publishable_sTcOrSy3ODTZyPOjUHLlHg_j6uS7P9N';

final FlutterLocalNotificationsPlugin _localNotif = FlutterLocalNotificationsPlugin();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await _setupForegroundNotifications();

  try {
    await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey, debug: true);
  } catch (e) {
    debugPrint("Supabase Initialization Error: $e");
  }

  RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();

  if (initialMessage != null) {
    Future.delayed(const Duration(seconds: 1), () {
      _handleNotificationTap();
    });
  }

  await Supabase.instance.client.auth.signOut();

  runApp(const ProviderScope(child: GyanshalaApp()));
}

Future<void> _setupForegroundNotifications() async {
  await FirebaseMessaging.instance.requestPermission();

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await _localNotif.initialize(
    settings: initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse details) {
      _handleNotificationTap();
    },
  );

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    _handleNotificationTap();
  });

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    RemoteNotification? notification = message.notification;

    if (notification != null) {
      _localNotif.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel',
            'High Importance Notifications',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    }
  });
}

void _handleNotificationTap() {
  navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const SignupVerificationScreen()));
}
