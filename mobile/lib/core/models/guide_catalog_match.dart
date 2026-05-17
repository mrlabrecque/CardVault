class GuideCatalogMatchPayload {
  const GuideCatalogMatchPayload({
    required this.matched,
    required this.minConfidence,
    this.reason,
    this.confidence,
    this.candidatesEvaluated,
    this.searchQueryUsed,
    this.expectedParallel,
    this.gotVariant,
    this.resolvedVia,
    this.searchSet,
    this.searchMeta,
    this.alternateMatches,
    this.match,
    this.errorMessage,
    this.persistedMaster,
  });

  final bool matched;
  final double minConfidence;
  final String? reason;
  final double? confidence;
  final int? candidatesEvaluated;
  final String? searchQueryUsed;
  final String? expectedParallel;
  final String? gotVariant;
  final String? resolvedVia;
  final String? searchSet;
  final Map<String, dynamic>? searchMeta;
  final List<GuideCatalogMatchedRow>? alternateMatches;
  final GuideCatalogMatchedRow? match;
  final String? errorMessage;

  /// Present when catalog search was invoked with persist id: Edge persisted to Postgres
  /// and returned this row (keys match `MasterCard.fromJson` in `cards_service`).
  final Map<String, dynamic>? persistedMaster;

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;

  factory GuideCatalogMatchPayload.fromJson(Map<String, dynamic> json) {
    final matched = json['matched'] == true;
    final minConf = (json['minConfidence'] as num?)?.toDouble() ?? 0.9;
    Map<String, dynamic>? matchMap;
    final raw = json['match'];
    if (raw is Map) {
      matchMap = Map<String, dynamic>.from(raw);
    }
    List<GuideCatalogMatchedRow>? alternates;
    final altRaw = json['alternate_matches'];
    if (altRaw is List) {
      alternates = altRaw
          .whereType<Map>()
          .map((e) => GuideCatalogMatchedRow.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    Map<String, dynamic>? persisted;
    final pm = json['persisted_master'];
    if (pm is Map) persisted = Map<String, dynamic>.from(pm);

    return GuideCatalogMatchPayload(
      matched: matched,
      minConfidence: minConf,
      reason: json['reason'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      candidatesEvaluated: (json['candidates_evaluated'] as num?)?.toInt(),
      searchQueryUsed: json['search_query_used'] as String?,
      expectedParallel: json['expected_parallel'] as String?,
      gotVariant: json['got_variant'] as String?,
      resolvedVia: json['resolved_via'] as String?,
      searchSet: json['search_set'] as String?,
      searchMeta: json['search_meta'] is Map
          ? Map<String, dynamic>.from(json['search_meta'] as Map)
          : null,
      alternateMatches: alternates,
      match: matchMap != null ? GuideCatalogMatchedRow.fromJson(matchMap) : null,
      errorMessage: json['error'] as String?,
      persistedMaster: persisted,
    );
  }

  factory GuideCatalogMatchPayload.error(String message) {
    return GuideCatalogMatchPayload(
      matched: false,
      minConfidence: 0.9,
      errorMessage: message,
    );
  }

  Map<String, dynamic> toJson() => {
        'matched': matched,
        'minConfidence': minConfidence,
        if (reason != null) 'reason': reason,
        if (confidence != null) 'confidence': confidence,
        if (candidatesEvaluated != null) 'candidates_evaluated': candidatesEvaluated,
        if (searchQueryUsed != null) 'search_query_used': searchQueryUsed,
        if (expectedParallel != null) 'expected_parallel': expectedParallel,
        if (gotVariant != null) 'got_variant': gotVariant,
        if (resolvedVia != null) 'resolved_via': resolvedVia,
        if (searchSet != null) 'search_set': searchSet,
        if (searchMeta != null) 'search_meta': searchMeta,
        if (alternateMatches != null)
          'alternate_matches': alternateMatches!.map((e) => e.toJson()).toList(),
        if (match != null) 'match': match!.toJson(),
        if (errorMessage != null) 'error': errorMessage,
        if (persistedMaster != null) 'persisted_master': persistedMaster,
      };
}

class GuideCatalogMatchedRow {
  const GuideCatalogMatchedRow({
    this.cardId,
    this.description,
    this.player,
    this.set,
    this.number,
    this.variant,
    this.category,
    this.image,
    this.prices,
    this.reasoning,
    this.sales7d,
    this.sales30d,
    this.gain,
  });

  final String? cardId;
  final String? description;
  final String? player;
  final String? set;
  final String? number;
  final String? variant;
  final String? category;
  final String? image;
  final List<Map<String, dynamic>>? prices;
  final String? reasoning;
  /// Market fields from card-search row (may be null if API omits).
  final int? sales7d;
  final int? sales30d;
  final double? gain;

  static double? _parseGain(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) {
      final cleaned = v.replaceAll(RegExp(r'[^0-9.-]'), '');
      if (cleaned.isEmpty) return null;
      return double.tryParse(cleaned);
    }
    return null;
  }

  static int? _parseCount(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) {
      final cleaned = v.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleaned.isEmpty) return null;
      return int.tryParse(cleaned);
    }
    return null;
  }

  factory GuideCatalogMatchedRow.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>>? prices;
    final p = json['prices'];
    if (p is List) {
      prices = p
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return GuideCatalogMatchedRow(
      cardId: json['card_id'] as String?,
      description: json['description'] as String?,
      player: json['player'] as String?,
      set: json['set'] as String?,
      number: json['number'] as String?,
      variant: json['variant'] as String?,
      category: json['category'] as String?,
      image: json['image'] as String?,
      prices: prices,
      reasoning: json['reasoning'] as String?,
      sales7d: _parseCount(json['sales_7d'] ?? json['7 Day Sales'] ?? json['7_Day_Sales']),
      sales30d: _parseCount(json['sales_30d'] ?? json['30 Day Sales'] ?? json['30_Day_Sales']),
      gain: _parseGain(json['gain'] ?? json['Gain']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (cardId != null) 'card_id': cardId,
        if (description != null) 'description': description,
        if (player != null) 'player': player,
        if (set != null) 'set': set,
        if (number != null) 'number': number,
        if (variant != null) 'variant': variant,
        if (category != null) 'category': category,
        if (image != null) 'image': image,
        if (prices != null) 'prices': prices,
        if (reasoning != null) 'reasoning': reasoning,
        if (sales7d != null) 'sales_7d': sales7d,
        if (sales30d != null) 'sales_30d': sales30d,
        if (gain != null) 'gain': gain,
      };
}
