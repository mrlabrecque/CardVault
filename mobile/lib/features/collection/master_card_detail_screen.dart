import 'package:flutter/material.dart';

import '../../core/services/cards_service.dart';
import 'card_detail_screen.dart';

export 'card_detail_screen.dart' show MasterCardDetailArgs;

/// Catalog variant detail — delegates to [CardDetailScreen.catalog].
class MasterCardDetailScreen extends StatelessWidget {
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
    this.setId,
    this.parallelId,
    this.releaseId,
    this.openedFromScanResults,
    this.openedFromScanSingleRoute,
    this.resyncGuidePricesFromCatalog,
  });

  final MasterCard masterCard;
  final String parallelName;
  final int? parallelSerialMax;
  final bool parallelIsAuto;
  final String? releaseName;
  final String? setName;
  final int? year;
  final String? sport;
  final String? setId;
  final String? parallelId;
  final String? releaseId;
  final VoidCallback? onAddToCollection;
  final VoidCallback? onAddToWishlist;
  final bool? openedFromScanResults;
  final bool? openedFromScanSingleRoute;
  final bool? resyncGuidePricesFromCatalog;

  @override
  Widget build(BuildContext context) {
    return CardDetailScreen.catalog(
      key: key,
      catalog: MasterCardDetailArgs(
        masterCard: masterCard,
        parallelName: parallelName,
        parallelSerialMax: parallelSerialMax,
        parallelIsAuto: parallelIsAuto,
        releaseName: releaseName,
        setName: setName,
        year: year,
        sport: sport,
        setId: setId,
        parallelId: parallelId,
        releaseId: releaseId,
        onAddToCollection: onAddToCollection,
        onAddToWishlist: onAddToWishlist,
        openedFromScanResults: openedFromScanResults,
        openedFromScanSingleRoute: openedFromScanSingleRoute,
        resyncGuidePricesFromCatalog: resyncGuidePricesFromCatalog,
      ),
    );
  }
}
