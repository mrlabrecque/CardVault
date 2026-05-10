import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/card_attributes_wrap.dart';

/// Display data backing a [FullBleedHero]. Both the user-collection detail
/// (`UserCard`) and the catalog's master-card detail map their fields onto
/// this DTO so the hero stays one widget.
class HeroDetails {
  const HeroDetails({
    required this.player,
    required this.sport,
    this.cardNumber,
    this.imageUrl,
    this.parallel,
    this.year,
    this.releaseName,
    this.setName,
    this.serialNumber,
    this.serialMax,
    this.rookie = false,
    this.autograph = false,
    this.memorabilia = false,
    this.ssp = false,
    this.isGraded = false,
    this.grader,
    this.grade,
  });

  final String player;
  final String sport;
  final String? cardNumber;
  final String? imageUrl;

  /// Display parallel name. `null` or `'Base'` is treated as base (no chip).
  final String? parallel;
  final int? year;
  final String? releaseName;
  final String? setName;
  final String? serialNumber;
  final int? serialMax;
  final bool rookie;
  final bool autograph;
  final bool memorabilia;
  final bool ssp;
  final bool isGraded;
  final String? grader;
  final String? grade;
}

/// Burgundy gradient hero with full-bleed top — sits behind a transparent
/// AppBar. Used by both [ItemDetailScreen] (user copy) and
/// [MasterCardDetailScreen] (catalog).
class FullBleedHero extends StatelessWidget {
  const FullBleedHero({
    super.key,
    required this.details,
    required this.topInset,
  });

  final HeroDetails details;
  final double topInset;

  String get _sportEmoji => switch (details.sport.toLowerCase()) {
    'basketball' => '🏀',
    'baseball' => '⚾',
    'football' => '🏈',
    'hockey' => '🏒',
    'soccer' => '⚽',
    _ => '🏀',
  };

  @override
  Widget build(BuildContext context) {
    final imageUrl = details.imageUrl;
    final trimmedParallel = details.parallel?.trim();
    final parallelName = (trimmedParallel != null &&
            trimmedParallel.isNotEmpty &&
            trimmedParallel.toLowerCase() != 'base')
        ? trimmedParallel
        : null;
    final textTheme = Theme.of(context).textTheme;

    final metaParts = <String>[
      if (details.year != null) details.year.toString(),
      if (details.releaseName != null) details.releaseName!,
      if (details.setName != null && details.setName != details.releaseName)
        details.setName!,
    ];

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF800020), Color(0xFF3D0010)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, topInset + kToolbarHeight + 8, 20, 24),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: 180,
                      height: 252,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 180,
                      height: 252,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(_sportEmoji, style: const TextStyle(fontSize: 64)),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: details.player,
                style: textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              if (details.cardNumber != null)
                TextSpan(
                  text: '  #${details.cardNumber}',
                  style: textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ]),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (metaParts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              metaParts.join(' · '),
              style: textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.75),
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (parallelName != null) ...[
            const SizedBox(height: 4),
            Text(
              parallelName,
              style: textTheme.labelMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.70),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          CardAttributesWrap(
            rookie: details.rookie,
            autograph: details.autograph,
            memorabilia: details.memorabilia,
            ssp: details.ssp,
            isGraded: details.isGraded,
            gradeLabel: '${details.grader ?? 'PSA'} ${details.grade ?? ''}'.trim(),
            serialNumber: details.serialNumber,
            serialMax: details.serialMax,
            alignment: WrapAlignment.center,
          ),
        ],
      ),
    );
  }
}

/// Circular liquid-glass nav chrome for detail screens with a transparent
/// AppBar.
///
/// Two visual treatments selected by [onDarkSurface]:
///   * `true`  — wine-tinted smoked plate, white icon. For sitting on the
///     burgundy hero (light/system blur stacks otherwise read as flat gray
///     on a dark red background).
///   * `false` — light frosted plate, dark icon. For when the hero has
///     scrolled away and the AppBar floats over the page background.
///
/// Two distinct subtrees are crossfaded with [AnimatedSwitcher] keyed on
/// [onDarkSurface] instead of animating decoration deltas. That keeps the
/// blur, gradient, border, and icon color all in lockstep on every flip.
class GlassCircleIconButton extends StatelessWidget {
  const GlassCircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.iconSize = 18,
    this.onDarkSurface = true,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final double iconSize;
  final bool onDarkSurface;

  static const double size = 44;

  @override
  Widget build(BuildContext context) {
    final variant = KeyedSubtree(
      key: ValueKey<bool>(onDarkSurface),
      child: _GlassCircleVariant(
        icon: icon,
        iconSize: iconSize,
        onDarkSurface: onDarkSurface,
      ),
    );

    final button = SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeOut,
            child: variant,
          ),
          Material(
            color: Colors.transparent,
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(size / 2),
              onTap: onPressed,
            ),
          ),
        ],
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

class _GlassCircleVariant extends StatelessWidget {
  const _GlassCircleVariant({
    required this.icon,
    required this.iconSize,
    required this.onDarkSurface,
  });

  final IconData icon;
  final double iconSize;
  final bool onDarkSurface;

  @override
  Widget build(BuildContext context) {
    const size = GlassCircleIconButton.size;
    const r = size / 2;
    final outerRadius = BorderRadius.circular(r);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;

    final List<Color> plateColors;
    final Color borderColor;
    final Color iconColor;
    final List<Color> highlightColors;
    final BoxShadow dropShadow;

    if (onDarkSurface) {
      plateColors = [
        const Color(0xFF5C0A20).withValues(alpha: 0.58),
        const Color(0xFF1A0508).withValues(alpha: 0.72),
      ];
      borderColor = Colors.white.withValues(alpha: 0.20);
      iconColor = Colors.white;
      highlightColors = [
        Colors.white.withValues(alpha: 0.14),
        Colors.white.withValues(alpha: 0.02),
        Colors.transparent,
      ];
      dropShadow = BoxShadow(
        color: Colors.black.withValues(alpha: 0.28),
        blurRadius: 10,
        offset: const Offset(0, 3),
      );
    } else {
      plateColors = isDark
          ? [
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0.06),
            ]
          : [
              Colors.white.withValues(alpha: 0.55),
              Colors.white.withValues(alpha: 0.40),
            ];
      borderColor = isDark
          ? Colors.white.withValues(alpha: 0.18)
          : Colors.black.withValues(alpha: 0.08);
      iconColor = colors.onSurface;
      highlightColors = isDark
          ? [
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0.02),
              Colors.transparent,
            ]
          : [
              Colors.white.withValues(alpha: 0.32),
              Colors.white.withValues(alpha: 0.10),
              Colors.transparent,
            ];
      dropShadow = BoxShadow(
        color: Colors.black.withValues(alpha: 0.10),
        blurRadius: 12,
        offset: const Offset(0, 3),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: outerRadius,
        boxShadow: [dropShadow],
      ),
      child: ClipRRect(
        borderRadius: outerRadius,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: outerRadius,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: plateColors,
                  ),
                  border: Border.all(color: borderColor),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: outerRadius,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: highlightColors,
                      stops: const [0.0, 0.35, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: Icon(icon, size: iconSize, color: iconColor),
            ),
          ],
        ),
      ),
    );
  }
}
