import 'package:flutter/material.dart';

class OccasionLogo extends StatelessWidget {
  const OccasionLogo({super.key, this.size = 96, this.fit = BoxFit.contain});

  final double size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/occasion_logo.png',
      width: size,
      height: size,
      fit: fit,
      semanticLabel: 'Occasion',
    );
  }
}
