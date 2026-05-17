import 'package:flutter/material.dart';

import '../../../core/widgets/adaptive_list_card.dart';

/// Label + value row used on item and catalog card detail screens.
class DetailPropertyTile extends StatelessWidget {
  const DetailPropertyTile({super.key, required this.label, required this.value});

  final String label;
  final String value;

  static TextStyle? _metaLabelStyle(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return t.labelMedium?.copyWith(
      color: c.onSurface.withValues(alpha: 0.60),
      letterSpacing: 0.5,
      fontWeight: FontWeight.w500,
    );
  }

  static TextStyle? _valueStyle(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return t.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: c.onSurface,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AdaptiveListCard(
        margin: EdgeInsets.zero,
        cornerRadius: 12,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: _metaLabelStyle(context)),
              const SizedBox(height: 2),
              Text(value, style: _valueStyle(context)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section title matching [ItemDetailScreen] "Your copy" / "Value" headers.
class DetailSectionHeader extends StatelessWidget {
  const DetailSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
      ),
    );
  }
}
