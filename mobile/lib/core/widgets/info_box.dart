import 'package:flutter/material.dart';

class InfoBox extends StatelessWidget {
  const InfoBox({
    super.key,
    required this.child,
    this.color = const Color(0xFF800020), // Maroon default
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = 8.0,
  });

  final Widget child;
  final Color color;
  final EdgeInsets padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: child,
    );
  }
}
