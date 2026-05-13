import 'package:flutter/material.dart';

import 'adaptive_list_card.dart';

/// Inline icon + body callout for detail screens.
///
/// Visual chrome: an [AdaptiveListCard] with 12pt corners, **14×12** inner
/// padding, and a 20pt leading icon followed by a 10pt gap. Pass
/// [highlightBorderColor] for an emphasized outline (e.g. primary tint).
class InlineNoticeContainer extends StatelessWidget {
  const InlineNoticeContainer({
    super.key,
    required this.icon,
    required this.child,
    this.highlightBorderColor,
  });

  /// Leading icon. Use a 20pt [Icon] for parity with other detail notices.
  final Widget icon;

  /// Body content. A single [Text] renders as a one-line notice; a
  /// `Column(crossAxisAlignment: start)` of title + supporting copy works
  /// for multi-line callouts.
  final Widget child;
  final Color? highlightBorderColor;

  @override
  Widget build(BuildContext context) {
    return AdaptiveListCard(
      margin: EdgeInsets.zero,
      cornerRadius: 12,
      highlightBorderColor: highlightBorderColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            icon,
            const SizedBox(width: 10),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
