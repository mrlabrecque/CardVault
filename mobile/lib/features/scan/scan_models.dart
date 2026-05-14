// CardSight identify + grading models shared by ScanScreen, CatalogScreen, and routing.

// Catalog detection result model
class ImageScanMatchResult {
  final String confidence; // High, Medium, Low
  final ScannedCatalogCard card;
  final GradingInfo? grading;
  /// Normalized 0–1 when the API returns a numeric field; otherwise null.
  final double? matchScore;

  /// CardHedge `/v1/cards/image-search` match merged onto this detection (if any).
  final String? cardHedgeCardId;
  final String? cardHedgeVariant;
  final String? cardHedgeSetLabel;
  /// Visual similarity score from image search (0–1).
  final double? cardHedgeImageSimilarity;

  ImageScanMatchResult({
    required this.confidence,
    required this.card,
    this.grading,
    this.matchScore,
    this.cardHedgeCardId,
    this.cardHedgeVariant,
    this.cardHedgeSetLabel,
    this.cardHedgeImageSimilarity,
  });

  static double? _parseMatchScore(Map<String, dynamic> json) {
    const keys = [
      'matchScore',
      'score',
      'confidenceScore',
      'similarity',
      'probability',
    ];
    for (final k in keys) {
      final v = json[k];
      if (v is num) {
        final d = v.toDouble();
        if (d >= 0 && d <= 1) return d;
        if (d > 1 && d <= 100) return (d / 100).clamp(0.0, 1.0);
      }
    }
    return null;
  }

  static double? _parseChImageSimilarity(dynamic v) {
    if (v == null) return null;
    if (v is num) {
      final d = v.toDouble();
      if (d >= 0 && d <= 1) return d;
      if (d > 1 && d <= 100) return (d / 100).clamp(0.0, 1.0);
    }
    if (v is String) {
      final n = double.tryParse(v.replaceAll('%', '').trim());
      if (n == null) return null;
      if (n <= 1) return n.clamp(0.0, 1.0);
      return (n / 100).clamp(0.0, 1.0);
    }
    return null;
  }

  factory ImageScanMatchResult.fromJson(Map<String, dynamic> json) {
    final cardRaw = json['card'];
    final cardMap = cardRaw is Map<String, dynamic>
        ? Map<String, dynamic>.from(cardRaw)
        : Map<String, dynamic>.from(cardRaw as Map? ?? {});
    // Some responses put player on the detection object instead of inside `card`.
    final hasName = cardMap['name'] != null && cardMap['name'].toString().trim().isNotEmpty;
    if (!hasName) {
      for (final k in ['name', 'player', 'playerName', 'athlete', 'subject']) {
        final v = json[k];
        if (v != null && v.toString().trim().isNotEmpty) {
          cardMap['name'] = v;
          break;
        }
      }
    }
    ScannedCatalogCard.mergeEnvelopeIntoCardMap(cardMap, json);
    return ImageScanMatchResult(
      confidence: json['confidence']?.toString() ?? 'Low',
      card: ScannedCatalogCard.fromJson(cardMap),
      grading: json['grading'] != null
          ? GradingInfo.fromJson(
              Map<String, dynamic>.from(json['grading'] as Map),
            )
          : null,
      matchScore: _parseMatchScore(json),
      cardHedgeCardId: json['cardHedgeCardId'] as String?,
      cardHedgeVariant: json['cardHedgeVariant'] as String?,
      cardHedgeSetLabel: json['cardHedgeSetLabel'] as String?,
      cardHedgeImageSimilarity: _parseChImageSimilarity(json['cardHedgeImageSimilarity']),
    );
  }

  /// Human-readable confidence for UI (prefers numeric % when available).
  String get confidenceLabel {
    final s = matchScore;
    if (s != null) return '${(s * 100).round()}%';
    return confidence;
  }

  ImageScanMatchResult copyWith({
    ScannedCatalogCard? card,
    String? cardHedgeCardId,
    String? cardHedgeVariant,
    String? cardHedgeSetLabel,
    double? cardHedgeImageSimilarity,
    bool clearCardHedge = false,
  }) {
    return ImageScanMatchResult(
      confidence: confidence,
      card: card ?? this.card,
      grading: grading,
      matchScore: matchScore,
      cardHedgeCardId: clearCardHedge ? null : (cardHedgeCardId ?? this.cardHedgeCardId),
      cardHedgeVariant: clearCardHedge ? null : (cardHedgeVariant ?? this.cardHedgeVariant),
      cardHedgeSetLabel: clearCardHedge ? null : (cardHedgeSetLabel ?? this.cardHedgeSetLabel),
      cardHedgeImageSimilarity: clearCardHedge ? null : (cardHedgeImageSimilarity ?? this.cardHedgeImageSimilarity),
    );
  }
}

class ScannedCatalogCard {
  final String? id; // exact match only
  final String? name; // player name (exact match only)
  final String? number; // card number (exact match only)
  final String? year;
  final String? manufacturer;
  final String? releaseName;
  final String? setName;
  final String? releaseId;
  final String? setId;
  /// CardSight catalog release key (vision spine). Prefer for [lazyImportCatalog] when [releaseId] is a vault UUID.
  final String? cardsightReleaseId;
  /// CardSight catalog set key (vision spine).
  final String? cardsightSetId;
  final String? segmentId;
  final ParallelInfo? parallel;
  final String? imageUrl;

  ScannedCatalogCard({
    this.id,
    this.name,
    this.number,
    this.year,
    this.manufacturer,
    this.releaseName,
    this.setName,
    this.releaseId,
    this.setId,
    this.cardsightReleaseId,
    this.cardsightSetId,
    this.segmentId,
    this.parallel,
    this.imageUrl,
  });

  ScannedCatalogCard copyWith({
    String? imageUrl,
    String? name,
    ParallelInfo? parallel,
    bool clearParallel = false,
    String? cardsightReleaseId,
    String? cardsightSetId,
    String? releaseId,
    String? setId,
  }) {
    return ScannedCatalogCard(
      id: id,
      name: name ?? this.name,
      number: number,
      year: year,
      manufacturer: manufacturer,
      releaseName: releaseName,
      setName: setName,
      releaseId: releaseId ?? this.releaseId,
      setId: setId ?? this.setId,
      cardsightReleaseId: cardsightReleaseId ?? this.cardsightReleaseId,
      cardsightSetId: cardsightSetId ?? this.cardsightSetId,
      segmentId: segmentId,
      parallel: clearParallel ? null : (parallel ?? this.parallel),
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  factory ScannedCatalogCard.fromJson(Map<String, dynamic> json) {
    return ScannedCatalogCard(
      id: _pickString(json, const ['id', 'cardId', 'card_id', 'masterCardId', 'master_card_id']),
      name: _pickString(json, const [
        'name',
        'player',
        'playerName',
        'player_name',
        'athlete',
        'subject',
        'playerLastName',
      ]),
      number: _pickString(json, const [
        'number',
        'cardNumber',
        'card_number',
        'cardNo',
        'card_no',
      ]),
      year: json['year']?.toString(),
      manufacturer: json['manufacturer']?.toString(),
      releaseName: _pickString(json, const [
        'releaseName',
        'release_name',
        'releaseTitle',
        'release_title',
      ]),
      setName: _pickString(json, const [
        'setName',
        'set_name',
        'checklistName',
        'checklist_name',
      ]),
      releaseId: _pickString(json, const [
        'releaseId',
        'release_id',
        'releaseUUID',
      ]),
      setId: _pickString(json, const [
        'setId',
        'set_id',
        'checklistId',
        'checklist_id',
      ]),
      cardsightReleaseId: _pickString(json, const [
        'cardsightReleaseId',
        'cardsight_release_id',
        'cardsightReleaseUUID',
      ]),
      cardsightSetId: _pickString(json, const [
        'cardsightSetId',
        'cardsight_set_id',
        'cardsightSetUUID',
      ]),
      segmentId: _pickString(json, const ['segmentId', 'segment_id', 'segment']),
      parallel: json['parallel'] != null
          ? ParallelInfo.fromJson(
              Map<String, dynamic>.from(json['parallel'] as Map),
            )
          : null,
      imageUrl: _pickString(json, const [
        'imageUrl',
        'image_url',
        'thumbnailUrl',
        'thumbnail',
        'image',
      ]),
    );
  }

  /// Copies release/set (and related) fields from the detection envelope or nested
  /// `release` / `set` objects into [card] when those keys are missing on `card`.
  static void mergeEnvelopeIntoCardMap(
    Map<String, dynamic> card,
    Map<String, dynamic> detection,
  ) {
    void putIfEmpty(String key, String? value) {
      if (value == null || value.isEmpty) return;
      final cur = card[key];
      if (cur != null && cur.toString().trim().isNotEmpty) return;
      card[key] = value;
    }

    void pickFrom(Map<String, dynamic> src, String dest, List<String> keys) {
      putIfEmpty(dest, _pickString(src, keys));
    }

    pickFrom(detection, 'cardsightReleaseId', const [
      'cardsightReleaseId',
      'cardsight_release_id',
      'cardsightReleaseUUID',
    ]);
    pickFrom(detection, 'cardsightSetId', const [
      'cardsightSetId',
      'cardsight_set_id',
      'cardsightSetUUID',
    ]);
    pickFrom(detection, 'releaseId', const [
      'releaseId',
      'release_id',
      'releaseUUID',
    ]);
    pickFrom(detection, 'setId', const [
      'setId',
      'set_id',
      'checklistId',
      'checklist_id',
    ]);
    pickFrom(detection, 'releaseName', const [
      'releaseName',
      'release_name',
      'releaseTitle',
    ]);
    pickFrom(detection, 'setName', const [
      'setName',
      'set_name',
      'checklistName',
    ]);
    pickFrom(detection, 'segmentId', const ['segmentId', 'segment_id', 'segment']);

    final rel = detection['release'];
    if (rel is Map) {
      final m = Map<String, dynamic>.from(rel);
      pickFrom(m, 'cardsightReleaseId', const [
        'cardsightReleaseId',
        'cardsight_release_id',
        'cardsightId',
        'cardsight_id',
      ]);
      pickFrom(m, 'releaseId', const ['id', 'releaseId', 'uuid']);
      pickFrom(m, 'releaseName', const ['name', 'title', 'displayName']);
    }
    final st = detection['set'];
    if (st is Map) {
      final m = Map<String, dynamic>.from(st);
      pickFrom(m, 'cardsightSetId', const [
        'cardsightSetId',
        'cardsight_set_id',
        'cardsightId',
        'cardsight_id',
      ]);
      pickFrom(m, 'setId', const ['id', 'setId', 'checklistId', 'uuid']);
      pickFrom(m, 'setName', const ['name', 'title', 'displayName']);
    }
  }

  /// Identify APIs use inconsistent keys; use the first non-empty string.
  static String? _pickString(Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }
}

class ParallelInfo {
  final String id;
  final String name;
  final int? numberedTo;

  ParallelInfo({required this.id, required this.name, this.numberedTo});

  factory ParallelInfo.fromJson(Map<String, dynamic> json) {
    return ParallelInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Base',
      numberedTo: json['numberedTo'],
    );
  }
}

class GradingInfo {
  final String confidence;
  final GradingCompany company;
  /// e.g. PSA numeric label from `grading.grade.value`
  final String? gradeValue;
  /// e.g. "GEM MINT" from `grading.grade.condition`
  final String? gradeCondition;

  GradingInfo({
    required this.confidence,
    required this.company,
    this.gradeValue,
    this.gradeCondition,
  });

  /// One line for UI: `PSA · 10 · GEM MINT`
  String get slabSummary {
    final parts = <String>[company.name];
    final v = gradeValue?.trim();
    final c = gradeCondition?.trim();
    if (v != null && v.isNotEmpty) parts.add(v);
    if (c != null && c.isNotEmpty) parts.add(c);
    return parts.join(' · ');
  }

  factory GradingInfo.fromJson(Map<String, dynamic> json) {
    String? gradeValue;
    String? gradeCondition;
    final gradeRaw = json['grade'];
    if (gradeRaw is Map) {
      final g = Map<String, dynamic>.from(gradeRaw);
      final v = g['value']?.toString().trim();
      final cond = g['condition']?.toString().trim();
      if (v != null && v.isNotEmpty) gradeValue = v;
      if (cond != null && cond.isNotEmpty) gradeCondition = cond;
    }
    return GradingInfo(
      confidence: json['confidence']?.toString() ?? 'Low',
      company: GradingCompany.fromJson(
        Map<String, dynamic>.from(json['company'] as Map? ?? {}),
      ),
      gradeValue: gradeValue,
      gradeCondition: gradeCondition,
    );
  }
}

class GradingCompany {
  final String? id;
  final String name;

  GradingCompany({this.id, required this.name});

  factory GradingCompany.fromJson(Map<String, dynamic> json) {
    return GradingCompany(id: json['id'], name: json['name'] ?? 'Unknown');
  }
}
