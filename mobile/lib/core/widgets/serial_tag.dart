import 'package:flutter/material.dart';

class SerialTag extends StatelessWidget {
  const SerialTag({super.key, this.serialNumber, this.serialMax});
  final String? serialNumber;
  final int? serialMax;

  static BoxDecoration _decoration(int? max) {
    if (max == 1) {
      return BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFBBF24), Color(0xFFFDE68A)]),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
      );
    }
    final color = switch (max) {
      int n when n <= 5   => const Color(0xFF7C3AED),
      int n when n <= 10  => const Color(0xFFE11D48),
      int n when n <= 25  => const Color(0xFFF97316),
      int n when n <= 50  => const Color(0xFF3B82F6),
      int n when n <= 99  => const Color(0xFF38BDF8),
      int n when n <= 199 => const Color(0xFF94A3B8),
      _ => const Color(0xFFE5E7EB),
    };
    return BoxDecoration(color: color, borderRadius: BorderRadius.circular(999));
  }

  static Color _textColor(int? max) {
    if (max == null || max >= 200) return const Color(0xFF6B7280);
    if (max == 1) return const Color(0xFF92400E);
    return Colors.white;
  }

  String get _label {
    if (serialNumber != null && serialMax != null) return '$serialNumber/$serialMax';
    if (serialMax != null) return '/$serialMax';
    if (serialNumber != null) return serialNumber!;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (_label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: _decoration(serialMax),
      child: Text(_label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _textColor(serialMax))),
    );
  }
}
