enum SaleType { auction, fixedPrice, bestOffer }

class Comp {
  final String title;
  final double price;
  final String currency;
  final DateTime? soldAt;
  final SaleType saleType;
  final String? url;
  final String? imageUrl;
  final String? grade; // 'Raw', 'PSA 10', 'PSA 9', 'PSA 9.5', 'BGS 9.5', 'Graded', etc.

  const Comp({
    required this.title,
    required this.price,
    required this.currency,
    this.soldAt,
    required this.saleType,
    this.url,
    this.imageUrl,
    this.grade,
  });

  factory Comp.fromJson(Map<String, dynamic> json) => Comp(
        title: json['title'] as String? ?? '',
        price: _parsePrice(json['price']),
        currency: json['currency'] as String? ?? 'USD',
        soldAt: json['sold_at'] != null ? DateTime.tryParse(json['sold_at'] as String) : null,
        saleType: _parseSaleType(json['sale_type'] as String?),
        url: json['url'] as String?,
        imageUrl: json['image_url'] as String?,
        grade: json['grade'] as String?,
      );

  static double _parsePrice(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is Map) return double.tryParse(raw['value']?.toString() ?? '0') ?? 0.0;
    return 0.0;
  }

  static SaleType _parseSaleType(String? raw) => switch (raw) {
    'auction'     => SaleType.auction,
    'best_offer'  => SaleType.bestOffer,
    _             => SaleType.fixedPrice,
  };
}

class LookupHistory {
  final String id;
  final String query;
  final List<Comp> results;
  final DateTime timestamp;

  const LookupHistory({
    required this.id,
    required this.query,
    required this.results,
    required this.timestamp,
  });

  factory LookupHistory.fromJson(Map<String, dynamic> json) => LookupHistory(
        id: json['id'] as String,
        query: json['query'] as String? ?? '',
        results: ((json['results'] as List?) ?? [])
            .map((r) => Comp.fromJson(r as Map<String, dynamic>))
            .toList(),
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      );

  double? get avgPrice {
    if (results.isEmpty) return null;
    return results.fold(0.0, (s, c) => s + c.price) / results.length;
  }
}

/// Live eBay listing row from `card-active-listings` Edge Function.
class ActiveListing {
  final String title;
  final double price;
  final String listingType;
  final String? url;
  final String? imageUrl;
  final String? ebayItemId;
  final DateTime? endsAt;

  const ActiveListing({
    required this.title,
    required this.price,
    required this.listingType,
    this.url,
    this.imageUrl,
    this.ebayItemId,
    this.endsAt,
  });

  factory ActiveListing.fromJson(Map<String, dynamic> json) {
    return ActiveListing(
      title: json['title']?.toString() ?? '',
      price: _parseActivePrice(json['price']),
      listingType: (json['listing_type']?.toString() ?? 'FIXED_PRICE').toUpperCase(),
      url: json['url']?.toString(),
      imageUrl: json['image_url']?.toString(),
      ebayItemId: json['ebay_item_id']?.toString(),
      endsAt: _parseOptionalDate(
        json['itemEndDate'] ?? json['item_end_date'] ?? json['ends_at'],
      ),
    );
  }

  static DateTime? _parseOptionalDate(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static double _parseActivePrice(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw) ?? 0;
    return 0;
  }

  bool get isAuction => listingType == 'AUCTION';

  bool get isBestOffer => listingType == 'BEST_OFFER';
}
