import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UpdateService {
  static Future<void> checkForUpdates(BuildContext context) async {
    if (kDebugMode) return;

    try {
      final data = await Supabase.instance.client
          .from('app_versions')
          .select()
          .order('version_code', ascending: false)
          .limit(1)
          .single();

      final int latestVersionCode = data['version_code'];
      final String apkUrl = data['apk_url'];
      final bool isForced = data['is_forced'];
      final String notes =
          data['release_notes'] ?? "New features and bug fixes.";

      final packageInfo = await PackageInfo.fromPlatform();
      final int currentVersionCode = int.parse(packageInfo.buildNumber);

      if (latestVersionCode > currentVersionCode) {
        if (!context.mounted) return;

        _showUpdateDialog(context, apkUrl, isForced, notes);
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }

  static void _showUpdateDialog(
    BuildContext context,
    String url,
    bool isForced,
    String notes,
  ) {
    showDialog(
      context: context,
      barrierDismissible: !isForced,
      builder: (context) => PopScope(
        canPop: !isForced,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
        },
        child: AlertDialog(
          title: const Text('Update Available'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('A new version of the app is ready to install.'),
              const SizedBox(height: 10),
              const Text(
                'What\'s new:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(notes),
            ],
          ),
          actions: [
            if (!isForced)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Later'),
              ),
            ElevatedButton(
              onPressed: () {
                if (!isForced) Navigator.pop(context);
                _executeOtaUpdate(url);
              },
              child: const Text('Update Now'),
            ),
          ],
        ),
      ),
    );
  }

  static void _executeOtaUpdate(String url) {
    try {
      OtaUpdate()
          .execute(url, destinationFilename: 'gyanshala_update.apk')
          .listen((OtaEvent event) {
            debugPrint('Update status: ${event.status}');
          });
    } catch (e) {
      debugPrint('OTA Update failed: $e');
    }
  }
}
