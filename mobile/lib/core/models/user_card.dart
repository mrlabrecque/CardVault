class UserCard {
  final String id;
  final String? masterCardId;
  final String player;
  final String? cardNumber;
  final String sport;
  final String? set;
  final String? checklist;
  final int? year;
  final String? setId;
  final String parallel;
  final String? parallelId;
  final String? grade;
  final bool isGraded;
  final String? grader;
  final double? gradeValue;
  final String? serialNumber;
  final int? serialMax;
  final double? pricePaid;
  final double? currentValue;
  final double? previousValue;
  final bool rookie;
  final bool autograph;
  final bool memorabilia;
  final bool ssp;
  final String? imageUrl;
  final DateTime? createdAt;
  final int? setCardCount;
  final bool weeklyPriceCheck;
  final DateTime? valueRefreshedAt;

  const UserCard({
    required this.id,
    this.masterCardId,
    required this.player,
    this.cardNumber,
    required this.sport,
    this.set,
    this.checklist,
    this.year,
    this.setId,
    required this.parallel,
    this.parallelId,
    this.grade,
    required this.isGraded,
    this.grader,
    this.gradeValue,
    this.serialNumber,
    this.serialMax,
    this.pricePaid,
    this.currentValue,
    this.previousValue,
    required this.rookie,
    required this.autograph,
    required this.memorabilia,
    required this.ssp,
    this.imageUrl,
    this.createdAt,
    this.setCardCount,
    this.weeklyPriceCheck = false,
    this.valueRefreshedAt,
  });

  factory UserCard.fromJson(Map<String, dynamic> json) {
    final master = json['master_card_definitions'] as Map<String, dynamic>?;
    final setData = master?['sets'] as Map<String, dynamic>?;
    final release = setData?['releases'] as Map<String, dynamic>?;
    final parallel = json['set_parallels'] as Map<String, dynamic>?;

    return UserCard(
      id: json['id'] as String,
      masterCardId: json['master_card_id'] as String?,
      player: master?['player'] as String? ?? '',
      cardNumber: master?['card_number'] as String?,
      sport: release?['sport'] as String? ?? '',
      set: release?['name'] as String?,        // release name e.g. "Topps Chrome"
      checklist: setData?['name'] as String?,  // set name e.g. "Base Set"
      year: release?['year'] as int?,
      setId: setData?['id'] as String?,
      setCardCount: setData?['card_count'] as int?,
      parallel: json['parallel_name'] as String? ?? 'Base',
      parallelId: json['parallel_id'] as String?,
      grade: json['grade_value'] as String?,
      isGraded: json['is_graded'] as bool? ?? false,
      grader: json['grader'] as String?,
      gradeValue: (json['grade_value'] as num?)?.toDouble(),
      serialNumber: json['serial_number'] as String?,
      serialMax: parallel?['serial_max'] as int? ?? master?['serial_max'] as int?,
      pricePaid: (json['price_paid'] as num?)?.toDouble(),
      currentValue: (json['current_value'] as num?)?.toDouble(),
      previousValue: (json['previous_value'] as num?)?.toDouble(),
      rookie: master?['is_rookie'] as bool? ?? false,
      autograph: master?['is_auto'] as bool? ?? false,
      memorabilia: master?['is_patch'] as bool? ?? false,
      ssp: master?['is_ssp'] as bool? ?? false,
      imageUrl: master?['image_url'] as String?,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      weeklyPriceCheck: json['weekly_price_check'] as bool? ?? false,
      valueRefreshedAt: json['value_refreshed_at'] != null ? DateTime.tryParse(json['value_refreshed_at'] as String) : null,
    );
  }

  double get pl => (currentValue ?? 0) - (pricePaid ?? 0);
  double get plPct => pricePaid != null && pricePaid! > 0 ? (pl / pricePaid!) * 100 : 0;

  /// 1 = up, -1 = down, 0 = flat/unknown
  int get valueTrend {
    if (previousValue == null || previousValue == currentValue) return 0;
    return (currentValue ?? 0) > previousValue! ? 1 : -1;
  }
}

class CardStack {
  final String? masterCardId;
  final String player;
  final String? cardNumber;
  final String? grade;
  final String parallel;
  final String? parallelId;
  final int qty;
  final double totalCost;
  final double totalValue;
  final double? totalPreviousValue;
  final bool rookie;
  final bool autograph;
  final bool memorabilia;
  final bool ssp;
  final String? imageUrl;
  final String sport;
  final String? set;
  final String? checklist;
  final int? year;
  final int? serialMax;
  final List<UserCard> cards;
  final DateTime? latestCreatedAt;

  const CardStack({
    this.masterCardId,
    required this.player,
    this.cardNumber,
    this.grade,
    required this.parallel,
    this.parallelId,
    required this.qty,
    required this.totalCost,
    required this.totalValue,
    this.totalPreviousValue,
    required this.rookie,
    required this.autograph,
    required this.memorabilia,
    required this.ssp,
    this.imageUrl,
    required this.sport,
    this.set,
    this.checklist,
    this.year,
    this.serialMax,
    required this.cards,
    this.latestCreatedAt,
  });

  String get stackKey => '${masterCardId}__${parallel}__${grade}__${cards.first.gradeValue}';

  double get avgCost => qty > 0 ? totalCost / qty : 0;
  double get pl => totalValue - totalCost;
  double get plPct => totalCost > 0 ? (pl / totalCost) * 100 : 0;

  /// 1 = up, -1 = down, 0 = flat/unknown
  int get valueTrend {
    if (totalPreviousValue == null || totalPreviousValue == totalValue) return 0;
    return totalValue > totalPreviousValue! ? 1 : -1;
  }

  /// % change from previous to current value; 0 if no prior data
  double get valueChangePct {
    if (totalPreviousValue == null || totalPreviousValue == 0) return 0;
    return (totalValue - totalPreviousValue!) / totalPreviousValue! * 100;
  }

  static List<CardStack> fromCards(List<UserCard> cards) {
    final Map<String, List<UserCard>> groups = {};
    for (final c in cards) {
      final key = '${c.masterCardId}__${c.parallel}__${c.grade}__${c.gradeValue}';
      groups.putIfAbsent(key, () => []).add(c);
    }
    return groups.values.map((group) {
      final first = group.first;
      final dates = group.where((c) => c.createdAt != null).map((c) => c.createdAt!).toList()
        ..sort((a, b) => b.compareTo(a));
      return CardStack(
        masterCardId: first.masterCardId,
        player: first.player,
        cardNumber: first.cardNumber,
        grade: first.grade,
        parallel: first.parallel,
        parallelId: first.parallelId,
        qty: group.length,
        totalCost: group.fold(0, (s, c) => s + (c.pricePaid ?? 0)),
        totalValue: group.fold(0, (s, c) => s + (c.currentValue ?? 0)),
        totalPreviousValue: group.any((c) => c.previousValue != null)
            ? group.fold<double>(0.0, (s, c) => s + (c.previousValue ?? c.currentValue ?? 0))
            : null,
        rookie: first.rookie,
        autograph: first.autograph,
        memorabilia: first.memorabilia,
        ssp: first.ssp,
        imageUrl: first.imageUrl,
        sport: first.sport,
        set: first.set,
        checklist: first.checklist,
        year: first.year,
        serialMax: first.serialMax,
        cards: group,
        latestCreatedAt: dates.isNotEmpty ? dates.first : null,
      );
    }).toList();
  }
}

// ── Set Tracker models ────────────────────────────────────────────────────────

class SetParallelRow {
  const SetParallelRow({
    required this.parallelName,
    required this.ownedCount,
    required this.cardCount,
    required this.pct,
    required this.totalValue,
  });
  final String parallelName;
  final int ownedCount;
  final int cardCount;
  final double pct;
  final double totalValue;
}

class SetRow {
  const SetRow({
    required this.setId,
    required this.setName,
    this.releaseName,
    this.year,
    this.sport,
    required this.cardCount,
    required this.ownedCount,
    required this.pct,
    required this.totalValue,
    required this.totalCost,
    this.imageUrl,
    required this.parallels,
  });
  final String setId;
  final String setName;
  final String? releaseName;
  final int? year;
  final String? sport;
  final int cardCount;
  final int ownedCount;
  final double pct;
  final double totalValue;
  final double totalCost;
  final String? imageUrl;
  final List<SetParallelRow> parallels;

  static List<SetRow> fromCards(List<UserCard> cards, {String sortBy = 'pct-desc'}) {
    // Only cards that belong to a tracked set with a known card count
    final tracked = cards.where((c) => c.setId != null && (c.setCardCount ?? 0) > 0);

    // setId → row data accumulators
    final rowMap = <String, _SetRowBuilder>{};

    for (final c in tracked) {
      final sid = c.setId!;
      rowMap.putIfAbsent(sid, () => _SetRowBuilder(
        setId: sid,
        setName: c.checklist ?? 'Base Set',
        releaseName: c.set,
        year: c.year,
        sport: c.sport,
        cardCount: c.setCardCount!,
      ));
      final row = rowMap[sid]!;

      // Track distinct masterCardIds per parallel
      final parallel = c.parallel;
      row.parallelMasters.putIfAbsent(parallel, () => <String?>{}).add(c.masterCardId);
      row.parallelValues[parallel] = (row.parallelValues[parallel] ?? 0) + (c.currentValue ?? 0);

      // Track overall distinct masterCardIds (across all parallels)
      row.allMasters.add(c.masterCardId);

      row.totalValue += c.currentValue ?? 0;
      row.totalCost  += c.pricePaid ?? 0;
      if (row.imageUrl == null && c.imageUrl != null) row.imageUrl = c.imageUrl;
    }

    final rows = rowMap.values.map((b) {
      final ownedCount = b.allMasters.length;
      final pct = (ownedCount / b.cardCount * 100).clamp(0, 100).toDouble();

      // Build per-parallel rows; Base first, then by % desc
      final parallelRows = b.parallelMasters.entries.map((e) {
        final owned = e.value.length;
        final ppct = (owned / b.cardCount * 100).clamp(0, 100).toDouble();
        return SetParallelRow(
          parallelName: e.key,
          ownedCount: owned,
          cardCount: b.cardCount,
          pct: ppct,
          totalValue: b.parallelValues[e.key] ?? 0,
        );
      }).toList()
        ..sort((a, b) {
          if (a.parallelName == 'Base') return -1;
          if (b.parallelName == 'Base') return 1;
          return b.pct.compareTo(a.pct);
        });

      return SetRow(
        setId: b.setId,
        setName: b.setName,
        releaseName: b.releaseName,
        year: b.year,
        sport: b.sport,
        cardCount: b.cardCount,
        ownedCount: ownedCount,
        pct: pct,
        totalValue: b.totalValue,
        totalCost: b.totalCost,
        imageUrl: b.imageUrl,
        parallels: parallelRows,
      );
    }).toList();

    rows.sort((a, b) => switch (sortBy) {
      'value-desc' => b.totalValue.compareTo(a.totalValue),
      'name'       => '${a.year}${a.releaseName}${a.setName}'.compareTo('${b.year}${b.releaseName}${b.setName}'),
      _            => b.pct.compareTo(a.pct), // pct-desc
    });

    return rows;
  }
}

class _SetRowBuilder {
  _SetRowBuilder({
    required this.setId,
    required this.setName,
    this.releaseName,
    this.year,
    this.sport,
    required this.cardCount,
  });
  final String setId;
  final String setName;
  final String? releaseName;
  final int? year;
  final String? sport;
  final int cardCount;
  double totalValue = 0;
  double totalCost = 0;
  String? imageUrl;
  final Set<String?> allMasters = {};
  final Map<String, Set<String?>> parallelMasters = {};
  final Map<String, double> parallelValues = {};
}
