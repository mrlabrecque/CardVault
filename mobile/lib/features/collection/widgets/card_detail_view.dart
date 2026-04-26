import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/user_card.dart';
import '../../../core/services/cards_service.dart';
import '../../../core/widgets/attr_tag.dart';
import '../../../core/widgets/serial_tag.dart';

enum CardDetailSection { hero, attributes, actions }

class CardDetailView extends StatelessWidget {
  const CardDetailView({
    super.key,
    this.userCard,
    this.masterCard,
    this.setName,
    this.releaseName,
    this.parallelName,
    this.year,
    this.sections = const [CardDetailSection.hero],
    this.onAddToCollection,
    this.onAddToWishlist,
    this.onEditCopy,
    this.onDelete,
    this.showYourCopy = false,
    this.isEditingCopy = false,
    this.yourCopyChild,
    this.children = const [],
  });

  final UserCard? userCard;
  final MasterCard? masterCard;
  final String? setName;
  final String? releaseName;
  final String? parallelName;
  final int? year;
  final List<CardDetailSection> sections;
  final VoidCallback? onAddToCollection;
  final VoidCallback? onAddToWishlist;
  final VoidCallback? onEditCopy;
  final VoidCallback? onDelete;
  final bool showYourCopy;
  final bool isEditingCopy;
  final Widget? yourCopyChild;
  final List<Widget> children;

  String get _sportEmoji => switch ((userCard?.sport ?? '').toLowerCase()) {
    'basketball' => '🏀',
    'baseball' => '⚾',
    'football' => '🏈',
    'hockey' => '🏒',
    'soccer' => '⚽',
    _ => '🃏',
  };

  String get _player => userCard?.player ?? masterCard?.player ?? '';
  String? get _cardNumber => userCard?.cardNumber ?? masterCard?.cardNumber;
  String? get _imageUrl => userCard?.imageUrl ?? masterCard?.imageUrl;
  String? get _set => userCard?.set ?? setName;
  String? get _checklist => userCard?.checklist;
  String? get _releaseName => releaseName;
  String? get _parallelName => userCard?.parallel ?? (parallelName != 'Base' ? parallelName : null);
  int? get _year => userCard?.year ?? year;
  bool get _isRookie => userCard?.rookie ?? masterCard?.isRookie ?? false;
  bool get _isAuto => userCard?.autograph ?? masterCard?.isAuto ?? false;
  bool get _isPatch => userCard?.memorabilia ?? masterCard?.isPatch ?? false;
  bool get _isSSP => userCard?.ssp ?? masterCard?.isSSP ?? false;
  bool get _isGraded => userCard?.isGraded ?? false;
  String? get _grade => userCard?.grade;
  String? get _grader => userCard?.grader;
  int? get _serialMax => userCard?.serialMax ?? masterCard?.serialMax;
  String? get _serialNumber => userCard?.serialNumber;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        if (sections.contains(CardDetailSection.hero))
          _buildCardHero(colors),
        if (sections.contains(CardDetailSection.attributes))
          ..._buildAttributes(colors),
        ...children,
        if (sections.contains(CardDetailSection.actions))
          ..._buildActions(colors),
      ],
    );
  }

  Widget _buildCardHero(ColorScheme colors) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF800020), Color(0xFF3D0010)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Card image
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: _imageUrl!,
                    width: 72,
                    height: 100,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 72,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(child: Text(_sportEmoji, style: const TextStyle(fontSize: 32))),
                  ),
          ),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: _player,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (_cardNumber != null)
                      TextSpan(
                        text: '  #$_cardNumber',
                        style: const TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w400),
                      ),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (_year != null) '$_year',
                    if (_releaseName != null) _releaseName,
                    if (_set != null && _set != _releaseName) _set,
                    if (_checklist != null) _checklist,
                  ].join(' · '),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_parallelName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _parallelName!,
                    style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (_isRookie) AttrTag('RC', color: const Color(0xFF16A34A)),
                    if (_isAuto) AttrTag('AUTO', color: const Color(0xFF7C3AED)),
                    if (_isPatch) AttrTag('PATCH', color: const Color(0xFF0369A1)),
                    if (_isSSP) AttrTag('SSP', color: const Color(0xFFB45309)),
                    if (_isGraded) AttrTag('${_grader ?? 'PSA'} ${_grade ?? ''}'),
                    SerialTag(serialNumber: _serialNumber, serialMax: _serialMax),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAttributes(ColorScheme colors) {
    return [
      const SizedBox(height: 20),
      const Divider(),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildActions(ColorScheme colors) {
    return [
      const SizedBox(height: 24),
      Row(
        children: [
          if (onAddToCollection != null)
            Expanded(
              child: FilledButton(
                onPressed: onAddToCollection,
                child: const Text('Add to Collection'),
              ),
            ),
          if (onAddToWishlist != null) ...[
            if (onAddToCollection != null) const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: onAddToWishlist,
                child: const Text('Add to Wishlist'),
              ),
            ),
          ],
        ],
      ),
    ];
  }
}
