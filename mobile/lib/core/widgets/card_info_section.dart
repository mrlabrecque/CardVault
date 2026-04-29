import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/attr_tag.dart';
import '../widgets/serial_tag.dart';

class CardInfoSection extends StatelessWidget {
  const CardInfoSection({
    super.key,
    required this.player,
    required this.cardNumber,
    required this.year,
    required this.set,
    required this.parallel,
    required this.attrs,
    required this.serialMax,
    required this.imageUrl,
    this.sport = 'Unknown',
    this.grade,
  });

  final String player;
  final String? cardNumber;
  final int? year;
  final String? set;
  final String? parallel;
  final List<String> attrs;
  final int? serialMax;
  final String? imageUrl;
  final String sport;
  final String? grade;

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
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        _buildImage(),
        const SizedBox(width: 12),
        Expanded(child: _buildInfo(colors)),
      ],
    );
  }

  Widget _buildImage() {
    if (imageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: imageUrl!,
          width: 44,
          height: 60,
          fit: BoxFit.cover,
          placeholder: (ctx, url) => _imagePlaceholder(),
          errorWidget: (ctx, url, err) => _imagePlaceholder(),
        ),
      );
    }
    return _imagePlaceholder();
  }

  Widget _imagePlaceholder() => Container(
        width: 44,
        height: 60,
        decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
        child: Center(child: Text(_sportEmoji, style: const TextStyle(fontSize: 20))),
      );

  Widget _buildInfo(ColorScheme colors) {
    return DefaultTextStyle(
      style: const TextStyle(color: Colors.black87),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: player, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            if (cardNumber != null)
              TextSpan(text: '  #$cardNumber', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: colors.onSurface.withValues(alpha: 0.5))),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        if (year != null || set != null)
          Text(
            [if (year != null) '$year', if (set != null) set].join(' · '),
            style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.6)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        if (parallel != null && parallel != 'Base')
          Text(parallel!, style: TextStyle(fontSize: 12, color: colors.primary)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final tag in attrs) AttrTag(tag, color: _attrColor(tag)),
            if (grade != null && grade!.isNotEmpty) AttrTag(grade!, color: const Color(0xFF9CA3AF)),
            if (serialMax != null) SerialTag(serialMax: serialMax),
          ],
        ),
      ],
      ),
    );
  }

  Color _attrColor(String tag) => switch (tag) {
    'RC'   => const Color(0xFF16A34A),
    'AUTO' => const Color(0xFF7C3AED),
    'PATCH'=> const Color(0xFF0369A1),
    'SSP'  => const Color(0xFFB45309),
    _      => const Color(0xFF6B7280),
  };
}
