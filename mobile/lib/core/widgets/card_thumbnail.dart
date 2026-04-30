import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CardThumbnail extends StatelessWidget {
  const CardThumbnail({
    super.key,
    required this.imageUrl,
    required this.sport,
    this.width = 60,
    this.height = 85,
    this.borderRadius = 6,
  });

  final String? imageUrl;
  final String sport;
  final double width;
  final double height;
  final double borderRadius;

  String get _sportEmoji => switch (sport.toLowerCase()) {
    'basketball' => '🏀',
    'baseball'   => '⚾',
    'football'   => '🏈',
    'hockey'     => '🏒',
    'soccer'     => '⚽',
    _            => '🏀',
  };

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(borderRadius),
          bottomLeft: Radius.circular(borderRadius),
        ),
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          width: width,
          height: height,
          fit: BoxFit.cover,
          placeholder: (_, _) => _placeholder(),
          errorWidget: (_, _, _) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Colors.grey.withValues(alpha: 0.15),
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(borderRadius),
        bottomLeft: Radius.circular(borderRadius),
      ),
    ),
    alignment: Alignment.center,
    child: Text(_sportEmoji, style: TextStyle(fontSize: width * 0.67)),
  );
}
