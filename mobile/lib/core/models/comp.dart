class Comp {
  final String title;
  final double price;
  final String currency;
  final DateTime soldAt;
  final String? url;
  final String? imageUrl;

  const Comp({
    required this.title,
    required this.price,
    required this.currency,
    required this.soldAt,
    this.url,
    this.imageUrl,
  });

  factory Comp.fromJson(Map<String, dynamic> json) => Comp(
        title: json['title'] as String? ?? '',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        currency: json['currency'] as String? ?? 'USD',
        soldAt: DateTime.tryParse(json['sold_at'] as String? ?? '') ?? DateTime.now(),
        url: json['url'] as String?,
        imageUrl: json['image_url'] as String?,
      );
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
