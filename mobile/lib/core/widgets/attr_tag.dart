import 'package:flutter/material.dart';

class AttrTag extends StatelessWidget {
  const AttrTag(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color != null ? Colors.white : Theme.of(context).colorScheme.onPrimaryContainer)),
    );
  }
}
