import 'package:flutter/material.dart';

import '../theme/fonts.dart';
import '../utils/currency_format.dart';

/// Primary USD line for collection-style list rows ([crossAxisAlignment]: end).
///
/// Uses the same [formatUsdOrNa] rules as other list surfaces (N/A when null / zero by default).
class ListItemUsdText extends StatelessWidget {
  const ListItemUsdText({
    super.key,
    required this.value,
    this.zeroIsNa = true,
    this.style,
    this.naLabel = 'N/A',
    this.textAlign = TextAlign.end,
  });

  final double? value;
  final bool zeroIsNa;
  final TextStyle? style;
  final String naLabel;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = formatUsdOrNa(value, zeroIsNa: zeroIsNa, naLabel: naLabel);
    final effectiveStyle = style ??
        TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: colors.onSurface,
          fontFamily: AppFonts.fontFamily,
        );
    final isNa = text == naLabel;
    return Text(
      text,
      textAlign: textAlign,
      style: effectiveStyle.copyWith(
        color: isNa ? colors.onSurface.withValues(alpha: 0.45) : effectiveStyle.color,
        fontWeight: isNa ? FontWeight.w600 : effectiveStyle.fontWeight,
      ),
    );
  }
}
