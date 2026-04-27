import 'package:flutter/material.dart';

class CardCountLabel extends StatelessWidget {
  const CardCountLabel({
    super.key,
    required this.total,
    this.shown,
  });

  final int total;
  final int? shown;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        '${total} ${total == 1 ? 'card' : 'cards'}'
        '${shown != null && shown != total ? ' · $shown shown' : ''}',
        style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.5)),
      ),
    );
  }
}
