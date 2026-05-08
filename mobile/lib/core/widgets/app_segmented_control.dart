import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';

enum AppSegmentedControlPreset { chrome, compact, iconOnly }

/// Shared segmented control wrapper used across screens.
///
/// Keeping a single app-level component lets us standardize behavior and
/// visuals in one place as we tune iOS liquid-glass interactions.
class AppSegmentedControl extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onValueChanged,
    required this.color,
    this.segmentKey,
    this.sfSymbols,
    this.iconSize,
    this.shrinkWrap,
    this.preset = AppSegmentedControlPreset.chrome,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onValueChanged;
  final Color color;

  /// Optional stable key for the inner control to preserve animation state
  /// across parent chrome recompositions.
  final Key? segmentKey;
  final List<dynamic>? sfSymbols;
  final double? iconSize;
  final bool? shrinkWrap;
  final AppSegmentedControlPreset preset;

  @override
  Widget build(BuildContext context) {
    final resolvedIconSize = iconSize ??
        switch (preset) {
          AppSegmentedControlPreset.iconOnly => 16.0,
          AppSegmentedControlPreset.compact => 14.0,
          AppSegmentedControlPreset.chrome => null,
        };
    final resolvedShrinkWrap = shrinkWrap ??
        switch (preset) {
          AppSegmentedControlPreset.iconOnly => true,
          AppSegmentedControlPreset.compact => true,
          AppSegmentedControlPreset.chrome => false,
        };

    return AdaptiveSegmentedControl(
      key: segmentKey,
      labels: labels,
      selectedIndex: selectedIndex,
      onValueChanged: onValueChanged,
      color: color,
      sfSymbols: sfSymbols,
      iconSize: resolvedIconSize,
      shrinkWrap: resolvedShrinkWrap,
    );
  }
}
