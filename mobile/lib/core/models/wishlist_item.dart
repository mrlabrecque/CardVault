int? _tryParseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  if (value is num) return value.toInt();
  return null;
}

double? _tryParseDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value);
  if (value is num) return value.toDouble();
  return null;
}

class WishlistMatch {
  final String id;
  final String wishlistId;
  final String? ebayItemId;
  final String title;
  final double price;
  final String listingType; // 'AUCTION' | 'FIXED_PRICE'
  final String? url;
  final String? imageUrl;

  const WishlistMatch({
    required this.id,
    required this.wishlistId,
    this.ebayItemId,
    required this.title,
    required this.price,
    required this.listingType,
    this.url,
    this.imageUrl,
  });

  factory WishlistMatch.fromJson(Map<String, dynamic> json) => WishlistMatch(
        id: json['id'] as String,
        wishlistId: json['wishlist_id'] as String? ?? '',
        ebayItemId: json['ebay_item_id'] as String?,
        title: json['title'] as String? ?? '',
        price: _tryParseDouble(json['price']) ?? 0,
        listingType: json['listing_type'] as String? ?? 'FIXED_PRICE',
        url: json['url'] as String?,
        imageUrl: json['image_url'] as String?,
      );
}

class WishlistItem {
  final String id;
  final String? masterCardId;
  final String? releaseId;
  final String? setId;
  final String? player;
  final int? year;
  final String? sport;
  final String? setName;
  final String? parallel;
  final String? cardNumber;
  final bool isRookie;
  final bool isAuto;
  final bool isPatch;
  final int? serialMax;
  final String? grade;
  final String? imageUrl;
  final String? ebayQuery;
  final List<String> excludeTerms;
  final double? targetPrice;
  final String alertStatus; // 'active' | 'paused' | 'triggered'
  final double? lastSeenPrice;
  final DateTime? lastCheckedAt;
  final DateTime? createdAt;
  final List<WishlistMatch> matches;

  const WishlistItem({
    required this.id,
    this.masterCardId,
    this.releaseId,
    this.setId,
    this.player,
    this.year,
    this.sport,
    this.setName,
    this.parallel,
    this.cardNumber,
    required this.isRookie,
    required this.isAuto,
    required this.isPatch,
    this.serialMax,
    this.grade,
    this.imageUrl,
    this.ebayQuery,
    required this.excludeTerms,
    this.targetPrice,
    required this.alertStatus,
    this.lastSeenPrice,
    this.lastCheckedAt,
    this.createdAt,
    required this.matches,
  });

  bool get isTriggered => alertStatus == 'triggered';
  bool get isPaused => alertStatus == 'paused';
  double get savings => (targetPrice ?? 0) - (lastSeenPrice ?? 0);

  List<String> get attrs {
    final tags = <String>[];
    if (isRookie) tags.add('RC');
    if (isAuto) tags.add('AUTO');
    if (isPatch) tags.add('PATCH');
    if (serialMax != null) tags.add('/$serialMax');
    return tags;
  }

  factory WishlistItem.fromJson(Map<String, dynamic> json) {
    final rawMatches = json['wishlist_matches'] as List? ?? [];

    // Try to get image_url from master_card_definitions join, fall back to direct field
    String? imageUrl = json['image_url'] as String?;
    if (imageUrl == null) {
      final masterCard = json['master_card_definitions'] as Map<String, dynamic>?;
      imageUrl = masterCard?['image_url'] as String?;
    }

    return WishlistItem(
      id: json['id'] as String,
      masterCardId: json['master_card_id'] as String?,
      releaseId: json['release_id'] as String?,
      setId: json['set_id'] as String?,
      player: json['player'] as String?,
      year: _tryParseInt(json['year']),
      sport: json['sport'] as String?,
      setName: json['set_name'] as String?,
      parallel: json['parallel'] as String?,
      cardNumber: json['card_number'] as String?,
      isRookie: json['is_rookie'] as bool? ?? false,
      isAuto: json['is_auto'] as bool? ?? false,
      isPatch: json['is_patch'] as bool? ?? false,
      serialMax: _tryParseInt(json['serial_max']),
      grade: json['grade'] as String?,
      imageUrl: imageUrl,
      ebayQuery: json['ebay_query'] as String?,
      excludeTerms: (json['exclude_terms'] as List?)?.cast<String>() ?? [],
      targetPrice: _tryParseDouble(json['target_price']),
      alertStatus: json['alert_status'] as String? ?? 'active',
      lastSeenPrice: _tryParseDouble(json['last_seen_price']),
      lastCheckedAt: json['last_checked_at'] != null
          ? DateTime.tryParse(json['last_checked_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      matches: rawMatches
          .map((m) => WishlistMatch.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }

  WishlistItem copyWith({String? alertStatus, List<WishlistMatch>? matches, double? lastSeenPrice}) =>
      WishlistItem(
        id: id, player: player, year: year, setName: setName, parallel: parallel,
        cardNumber: cardNumber, isRookie: isRookie, isAuto: isAuto, isPatch: isPatch,
        serialMax: serialMax, grade: grade, ebayQuery: ebayQuery, excludeTerms: excludeTerms,
        targetPrice: targetPrice,
        alertStatus: alertStatus ?? this.alertStatus,
        lastSeenPrice: lastSeenPrice ?? this.lastSeenPrice,
        lastCheckedAt: lastCheckedAt, createdAt: createdAt,
        matches: matches ?? this.matches,
      );
}
