import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // Added this
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // Added this
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyanshala_app/features/auth/presentation/screens/signup_verification_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'firebase_options.dart';

const _supabaseUrl = 'https://ntrniclejneisdzepntv.supabase.co';
const _supabaseAnonKey = 'sb_publishable_sTcOrSy3ODTZyPOjUHLlHg_j6uS7P9N';

// Global instance for local notifications
final FlutterLocalNotificationsPlugin _localNotif =
    FlutterLocalNotificationsPlugin();

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 2. Setup Foreground Notification Handling
  await _setupForegroundNotifications();

  // 3. Initialize Supabase
  try {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
      debug: true,
    );
    debugPrint("Supabase initialized successfully");
  } catch (e) {
    debugPrint("Supabase Initialization Error: $e");
  }

  // Check if the app was opened from a terminated state via a notification
  RemoteMessage? initialMessage = await FirebaseMessaging.instance
      .getInitialMessage();

  if (initialMessage != null) {
    // Give the app a second to load the UI before pushing the screen
    Future.delayed(const Duration(seconds: 1), () {
      _handleNotificationTap();
    });
  }

  // FORCE LOGOUT ON STARTUP
  // This ensures that every time the app process starts fresh,
  // the session is cleared and the user sees the Login/Signup screen.
  await Supabase.instance.client.auth.signOut();

  runApp(
    // This is the missing piece!
    const ProviderScope(child: GyanshalaApp()),
  );
}

/// The secret sauce to make banners appear while app is open
Future<void> _setupForegroundNotifications() async {
  // Request permission (Required for iOS and Android 13+)
  await FirebaseMessaging.instance.requestPermission();

  // Initialize Local Notifications settings
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await _localNotif.initialize(
    settings: initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse details) {
      _handleNotificationTap();
    },
  );

  // Also handle the case where the app was totally closed and opened via notification
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    _handleNotificationTap();
  });

  // Listen for the message while app is in foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    RemoteNotification? notification = message.notification;

    if (notification != null) {
      _localNotif.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel', // Match this in your AndroidManifest
            'High Importance Notifications',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    }
  });
}

// The navigation logic
void _handleNotificationTap() {
  navigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => const SignupVerificationScreen()),
  );
}
