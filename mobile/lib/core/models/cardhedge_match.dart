class CardHedgeMatchPayload {
  const CardHedgeMatchPayload({
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
  final List<CardHedgeMatchedCard>? alternateMatches;
  final CardHedgeMatchedCard? match;
  final String? errorMessage;

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;

  factory CardHedgeMatchPayload.fromJson(Map<String, dynamic> json) {
    final matched = json['matched'] == true;
    final minConf = (json['minConfidence'] as num?)?.toDouble() ?? 0.9;
    Map<String, dynamic>? matchMap;
    final raw = json['match'];
    if (raw is Map) {
      matchMap = Map<String, dynamic>.from(raw);
    }
    List<CardHedgeMatchedCard>? alternates;
    final altRaw = json['alternate_matches'];
    if (altRaw is List) {
      alternates = altRaw
          .whereType<Map>()
          .map((e) => CardHedgeMatchedCard.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return CardHedgeMatchPayload(
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
      match: matchMap != null ? CardHedgeMatchedCard.fromJson(matchMap) : null,
      errorMessage: json['error'] as String?,
    );
  }

  factory CardHedgeMatchPayload.error(String message) {
    return CardHedgeMatchPayload(
      matched: false,
      minConfidence: 0.9,
      errorMessage: message,
    );
  }
}

class CardHedgeMatchedCard {
  const CardHedgeMatchedCard({
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

  factory CardHedgeMatchedCard.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>>? prices;
    final p = json['prices'];
    if (p is List) {
      prices = p
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return CardHedgeMatchedCard(
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
    );
  }
}
