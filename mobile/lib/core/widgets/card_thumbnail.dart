import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// List-row card image (collection, wishlist, grading, lot builder).
///
/// [ConstrainedBox] keeps width/height from collapsing before the network image
/// has intrinsic dimensions (CDN / slab thumbnails).
class CardThumbnail extends StatelessWidget {
  const CardThumbnail({
    super.key,
    required this.imageUrl,
    required this.sport,
    this.width = listRowWidth,
    this.height = double.infinity,
    this.borderRadius = 6,
  });

  /// List rows — wide enough for slab-style art.
  static const double listRowWidth = 100;

  final String? imageUrl;
  final String sport;
  final double width;

  /// When [height] is omitted, height follows standard trading-card portrait (2.5 × 3.5).
  final double height;
  final double borderRadius;

  String? get _resolvedUrl {
    final t = imageUrl?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  double get _thumbHeight =>
      height == double.infinity ? width * 3.5 / 2.5 : height;

  String get _sportEmoji => switch (sport.toLowerCase()) {
        'basketball' => '🏀',
        'baseball' => '⚾',
        'football' => '🏈',
        'hockey' => '🏒',
        'soccer' => '⚽',
        _ => '🏀',
      };

  @override
  Widget build(BuildContext context) {
    final url = _resolvedUrl;
    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(borderRadius),
        bottomLeft: Radius.circular(borderRadius),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints.tightFor(width: width, height: _thumbHeight),
        child: url != null ? _networkImage(url) : _placeholder(),
      ),
    );
  }

  Widget _networkImage(String url) {
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: _thumbHeight,
      fit: BoxFit.cover,
      placeholder: (_, _) => _placeholder(),
      errorWidget: (_, _, _) => _placeholder(),
    );
  }

  Widget _placeholder() => ColoredBox(
        color: Colors.grey.withValues(alpha: 0.15),
        child: Center(
          child: Text(_sportEmoji, style: TextStyle(fontSize: width * 0.5)),
        ),
      );
}
