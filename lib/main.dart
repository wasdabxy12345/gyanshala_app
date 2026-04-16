import 'package:flutter/material.dart';
import 'package:gyanshala_app/features/auth/presentation/screens/signup_verification_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // Added this
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // Added this
import 'firebase_options.dart';
import 'app.dart';

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

  runApp(const GyanshalaApp());
}

/// The secret sauce to make banners appear while app is open
Future<void> _setupForegroundNotifications() async {
  // Request permission (Required for iOS and Android 13+)
  await FirebaseMessaging.instance.requestPermission();

  // Initialize Local Notifications settings
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);
  await _localNotif.initialize(
    initSettings,
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
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
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
