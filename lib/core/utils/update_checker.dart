import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateChecker {
  static const String _repoUrl = 'https://api.github.com/repos/wasdabxy12345/gyanshala_app/releases/latest';
  static Future<String?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final response = await http.get(Uri.parse(_repoUrl));
      if (response.statusCode != 200) return null;

      final Map<String, dynamic> releaseData = jsonDecode(response.body);
      final String latestVersion = (releaseData['tag_name'] as String).replaceAll('v', '').trim(); // Cleans "v1.0.1" to "1.0.1"

      if (_isNewerVersion(currentVersion, latestVersion)) {
        final List<dynamic> assets = releaseData['assets'];
        final apkAsset = assets.firstWhere((asset) => asset['name'].toString().endsWith('.apk'), orElse: () => null);

        if (apkAsset != null) {
          return apkAsset['browser_download_url'] as String;
        }
      }
    } catch (e) {
      print('Error checking for updates: $e');
    }
    return null;
  }

  static bool _isNewerVersion(String current, String latest) {
    List<int> currentParts = current.split('.').map(int.parse).toList();
    List<int> latestParts = latest.split('.').map(int.parse).toList();

    for (int i = 0; i < latestParts.length; i++) {
      if (i >= currentParts.length) return true;
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  static Future<void> downloadAndInstallApk(String url, Function(double) onProgress) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        print('Server error: ${response.statusCode}');
        client.close();
        return;
      }

      final contentLength = response.contentLength ?? 0;
      List<int> bytes = [];

      final directory = await getTemporaryDirectory();
      final apkPath = '${directory.path}/gyanshala_update.apk';
      final file = File(apkPath);
      await response.stream.listen(
        (chunk) {
          bytes.addAll(chunk);
          if (contentLength > 0) {
            final progress = bytes.length / contentLength;
            onProgress(progress);
          }
        },
        onDone: () async {
          await file.writeAsBytes(bytes);
          client.close();
          await OpenFilex.open(apkPath);
        },
        onError: (e) {
          client.close();
          throw e;
        },
        cancelOnError: true,
      );
    } catch (e) {
      print('APK Download/Install failed: $e');
    }
  }
}
