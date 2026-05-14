/// One guide-grade price row from CardHedge `card-details` (or backfill), attached to image-search hits.
class CardHedgeGuidePriceChip {
  const CardHedgeGuidePriceChip({required this.grade, required this.price});

  final String grade;
  final double price;

  factory CardHedgeGuidePriceChip.fromJson(Map<String, dynamic> j) {
    final g = (j['grade'] ?? j['Grade'] ?? '').toString().trim();
    final raw = j['price'] ?? j['Price'] ?? j['value'];
    final p = raw is num ? raw.toDouble() : double.tryParse(raw.toString().replaceAll(RegExp(r'[^0-9.-]'), '')) ?? 0;
    return CardHedgeGuidePriceChip(grade: g.isEmpty ? '—' : g, price: p);
  }
}

/// One row from Edge `cardhedge-image-search` (`hits[]`) or enriched `identify-card` candidates.
class CardHedgeImageSearchHit {
  const CardHedgeImageSearchHit({
    required this.cardId,
    this.similarityLabel,
    this.distance,
    this.player,
    this.setLabel,
    this.number,
    this.variant,
    this.category,
    this.description,
    this.image,
    this.prices = const [],
    this.cardsightReleaseId,
    this.cardsightSetId,
    this.spineMatchConfidence,
    this.spineMatchSource,
  });

  final String cardId;
  final String? similarityLabel;
  final double? distance;
  final String? player;
  final String? setLabel;
  final String? number;
  final String? variant;
  final String? category;
  final String? description;
  final String? image;
  final List<CardHedgeGuidePriceChip> prices;
  final String? cardsightReleaseId;
  final String? cardsightSetId;
  final double? spineMatchConfidence;
  final String? spineMatchSource;

  /// 0–1 (parses `"95.23"` percent strings from upstream).
  double get similarityScore {
    final raw = similarityLabel?.replaceAll('%', '').trim();
    if (raw == null || raw.isEmpty) return 0;
    final n = double.tryParse(raw);
    if (n == null) return 0;
    if (n <= 1) return n.clamp(0.0, 1.0);
    return (n / 100).clamp(0.0, 1.0);
  }

  factory CardHedgeImageSearchHit.fromJson(Map<String, dynamic> j) {
    final pricesRaw = j['prices'];
    final chips = <CardHedgeGuidePriceChip>[];
    if (pricesRaw is List) {
      for (final e in pricesRaw) {
        if (e is Map) {
          final c = CardHedgeGuidePriceChip.fromJson(Map<String, dynamic>.from(e));
          if (c.price > 0 && c.grade.isNotEmpty && c.grade != '—') chips.add(c);
        }
      }
    }
    final cr = j['cardsightReleaseId']?.toString().trim();
    final cs = j['cardsightSetId']?.toString().trim();
    return CardHedgeImageSearchHit(
      cardId: (j['card_id'] ?? j['cardId'] ?? '').toString().trim(),
      similarityLabel: j['similarity']?.toString(),
      distance: (j['distance'] is num) ? (j['distance'] as num).toDouble() : double.tryParse('${j['distance']}'),
      player: j['player']?.toString(),
      setLabel: j['set']?.toString(),
      number: j['number']?.toString(),
      variant: j['variant']?.toString(),
      category: j['category']?.toString(),
      description: j['description']?.toString(),
      image: j['image']?.toString(),
      prices: chips,
      cardsightReleaseId: (cr != null && cr.isNotEmpty) ? cr : null,
      cardsightSetId: (cs != null && cs.isNotEmpty) ? cs : null,
      spineMatchConfidence: (j['spineMatchConfidence'] is num)
          ? (j['spineMatchConfidence'] as num).toDouble()
          : double.tryParse('${j['spineMatchConfidence']}'),
      spineMatchSource: j['spineMatchSource']?.toString(),
    );
  }
}
