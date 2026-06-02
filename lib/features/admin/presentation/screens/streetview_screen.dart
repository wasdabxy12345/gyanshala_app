import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

class StreetViewScreen extends StatelessWidget {
  final LatLng position;
  const StreetViewScreen({super.key, required this.position});
  @override
  Widget build(BuildContext context) {
    final url = "https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=${position.latitude},${position.longitude}";
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            final url = request.url;
            if (url.startsWith("intent://")) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
    return Scaffold(
      appBar: AppBar(title: const Text("Street View")),
      body: WebViewWidget(controller: controller),
    );
  }
}
