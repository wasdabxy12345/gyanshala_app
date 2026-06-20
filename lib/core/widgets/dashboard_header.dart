import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final double logoHeight = (width * 0.13).clamp(37, 77);
        final double spacing = 0;
        final double horizontalPadding = width * (kIsWeb ? 0.3 : 0.03);

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Row(
            children: [
              Expanded(
                child: Image.asset('assets/images/gyanshala_logo.jpg', height: logoHeight, fit: BoxFit.contain),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: Image.asset('assets/images/unm_logo.jpg', height: logoHeight, fit: BoxFit.contain),
              ),
              SizedBox(width: spacing),
              Expanded(
                child: Image.asset('assets/images/shiksha_setu_logo.png', height: logoHeight, fit: BoxFit.contain),
              ),
            ],
          ),
        );
      },
    );
  }
}
