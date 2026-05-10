import 'package:flutter/material.dart';

import 'attr_tag.dart';
import 'serial_tag.dart';

class CardAttributePalette {
  static const rookie = Color(0xFF16A34A);
  static const auto = Color(0xFF7C3AED);
  static const patch = Color(0xFF0369A1);
  static const ssp = Color(0xFFB45309);
  static const grade = Color(0xFF9CA3AF);
}

class CardAttributesWrap extends StatelessWidget {
  const CardAttributesWrap({
    super.key,
    this.rookie = false,
    this.autograph = false,
    this.memorabilia = false,
    this.ssp = false,
    this.isGraded = false,
    this.gradeLabel,
    this.serialNumber,
    this.serialMax,
    this.alignment = WrapAlignment.start,
    this.spacing = 4,
    this.runSpacing = 4,
  });

  final bool rookie;
  final bool autograph;
  final bool memorabilia;
  final bool ssp;
  final bool isGraded;
  final String? gradeLabel;
  final String? serialNumber;
  final int? serialMax;
  final WrapAlignment alignment;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      alignment: alignment,
      children: [
        if (rookie) const AttrTag('RC', color: CardAttributePalette.rookie),
        if (autograph) const AttrTag('AUTO', color: CardAttributePalette.auto),
        if (memorabilia) const AttrTag('PATCH', color: CardAttributePalette.patch),
        if (ssp) const AttrTag('SSP', color: CardAttributePalette.ssp),
        if (isGraded && gradeLabel != null && gradeLabel!.trim().isNotEmpty)
          AttrTag(gradeLabel!.trim(), color: CardAttributePalette.grade),
        SerialTag(serialNumber: serialNumber, serialMax: serialMax),
      ],
    );
  }
}
