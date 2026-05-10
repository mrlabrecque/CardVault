import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/cards_service.dart';
import '../../core/theme/app_theme.dart';
import '../wishlist/wishlist_screen.dart';
import 'widgets/active_state_indicator.dart';
import 'widgets/full_bleed_card_hero.dart';
import 'widgets/market_analysis_section.dart';

/// Bottom scroll padding so the last section clears the floating tab bar
/// (matches `ItemDetailScreen`).
const double _kShellTabBarScrollInset = 100;

/// Args bundle passed via `GoRouter` `extra` when pushing
/// [MasterCardDetailScreen]. Using a typed DTO keeps the route definition in
/// `router.dart` decoupled from the screen's parameter list.
class MasterCardDetailArgs {
  const MasterCardDetailArgs({
    required this.masterCard,
    required this.parallelName,
    this.parallelSerialMax,
    this.parallelIsAuto = false,
    this.releaseName,
    this.setName,
    this.year,
    this.sport,
    this.onAddToCollection,
    this.onAddToWishlist,
  });

  final MasterCard masterCard;
  final String parallelName;
  final int? parallelSerialMax;
  final bool parallelIsAuto;
  final String? releaseName;
  final String? setName;
  final int? year;
  final String? sport;
  final VoidCallback? onAddToCollection;
  final VoidCallback? onAddToWishlist;
}

/// Read-only detail for a `master_card_definitions` entry — the same shell
/// as [ItemDetailScreen] minus the "Value" and "Your copy" sections, plus
/// "Add to Collection" / "Add to Wishlist" CTAs.
///
/// Pushed from `CatalogScreen` after the user reaches the final card +
/// parallel selection (in either browse or search flows).
class MasterCardDetailScreen extends ConsumerStatefulWidget {
  const MasterCardDetailScreen({
    super.key,
    required this.masterCard,
    required this.parallelName,
    this.parallelSerialMax,
    this.parallelIsAuto = false,
    this.releaseName,
    this.setName,
    this.year,
    this.sport,
    this.onAddToCollection,
    this.onAddToWishlist,
  });

  final MasterCard masterCard;
  final String parallelName;
  final int? parallelSerialMax;
  final bool parallelIsAuto;
  final String? releaseName;
  final String? setName;
  final int? year;
  final String? sport;
  final VoidCallback? onAddToCollection;
  final VoidCallback? onAddToWishlist;

  @override
  ConsumerState<MasterCardDetailScreen> createState() =>
      _MasterCardDetailScreenState();
}

class _MasterCardDetailScreenState
    extends ConsumerState<MasterCardDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _heroKey = GlobalKey();

  /// Scroll offset (px) at which the hero gradient is fully behind the AppBar.
  /// Re-measured from the rendered hero on every frame.
  double _heroSwitchThreshold = 320;
  bool _scrolledPastHero = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final past = _scrollController.offset > _heroSwitchThreshold;
    if (past != _scrolledPastHero) {
      setState(() => _scrolledPastHero = past);
    }
  }

  void _maybeMeasureHero() {
    final ctx = _heroKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final topInset = MediaQuery.paddingOf(context).top;
    final next = box.size.height - (topInset + kToolbarHeight) - 8;
    if ((next - _heroSwitchThreshold).abs() > 1) {
      _heroSwitchThreshold = next;
      _onScroll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final padding = MediaQuery.paddingOf(context);
    final bottomPad = padding.bottom;
    final topInset = padding.top;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeMeasureHero();
    });

    final onLight = _scrolledPastHero;
    final iconTint = onLight ? colors.onSurface : Colors.white;

    final masterCard = widget.masterCard;
    final parallel = widget.parallelName;

    final userCardsAsync = ref.watch(userCardsProvider);
    final copyCount = userCardsAsync.whenData((all) {
      return all.where((c) {
        final masterMatch = c.masterCardId == masterCard.id;
        final cardNumberMatch = (c.cardNumber?.trim() ?? '') ==
            (masterCard.cardNumber?.trim() ?? '');
        final parallelMatch = c.parallel.trim() == parallel.trim();
        return masterMatch && cardNumberMatch && parallelMatch;
      }).length;
    }).value ?? 0;

    final wishlistAsync = ref.watch(wishlistProvider);
    final inWishlist = wishlistAsync.whenData((wl) {
      return wl.any((w) {
        final playerMatch = (w.player?.trim().toLowerCase() ?? '') ==
            masterCard.player.trim().toLowerCase();
        final cardNumberMatch = (w.cardNumber?.trim() ?? '') ==
            (masterCard.cardNumber?.trim() ?? '');
        final parallelMatch =
            (w.parallel?.trim() ?? 'Base') == parallel.trim();
        return playerMatch && cardNumberMatch && parallelMatch;
      });
    }).value ?? false;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        forceMaterialTransparency: true,
        foregroundColor: iconTint,
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        iconTheme: IconThemeData(color: iconTint),
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Center(
            child: GlassCircleIconButton(
              icon: Icons.arrow_back_ios_new,
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: 'Back',
              iconSize: 17,
              onDarkSurface: !onLight,
            ),
          ),
        ),
      ),
      body: ListView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          FullBleedHero(
            key: _heroKey,
            topInset: topInset,
            details: HeroDetails(
              player: masterCard.player,
              sport: widget.sport ?? '',
              cardNumber: masterCard.cardNumber,
              imageUrl: masterCard.imageUrl,
              parallel: parallel,
              year: widget.year,
              releaseName: widget.releaseName,
              setName: widget.setName,
              serialMax: widget.parallelSerialMax ?? masterCard.serialMax,
              rookie: masterCard.isRookie,
              autograph: masterCard.isAuto || widget.parallelIsAuto,
              memorabilia: masterCard.isPatch,
              ssp: masterCard.isSSP,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              24,
              16,
              _kShellTabBarScrollInset + bottomPad,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: copyCount > 0
                          ? ActiveStateIndicator(
                              icon: Icons.check_circle,
                              label: 'In Collection ($copyCount)',
                            )
                          : AdaptiveButton.child(
                              onPressed: widget.onAddToCollection,
                              style: AdaptiveButtonStyle.filled,
                              color: AppTheme.primary,
                              child: const Text(
                                'Add to Collection',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: inWishlist
                          ? const ActiveStateIndicator(
                              icon: Icons.favorite,
                              label: 'In Wishlist',
                            )
                          : AdaptiveButton.child(
                              onPressed: widget.onAddToWishlist,
                              style: AdaptiveButtonStyle.bordered,
                              color: AppTheme.primary,
                              child: DefaultTextStyle.merge(
                                style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.favorite_border, size: 18, color: AppTheme.primary),
                                    SizedBox(width: 8),
                                    Text('Add to Wishlist'),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                MarketAnalysisSection(
                  masterCardId: masterCard.id,
                  parallelName: parallel,
                  initialGrade: 'Raw',
                  segmentColor: colors.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

