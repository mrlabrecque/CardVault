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
  final bool rookie;
  final bool autograph;
  final bool memorabilia;
  final bool ssp;
  final String? imageUrl;
  final DateTime? createdAt;

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
    required this.rookie,
    required this.autograph,
    required this.memorabilia,
    required this.ssp,
    this.imageUrl,
    this.createdAt,
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
      setId: setData?['id'] as String?,        // sets.id for parallel lookup
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
      rookie: master?['is_rookie'] as bool? ?? false,
      autograph: master?['is_auto'] as bool? ?? false,
      memorabilia: master?['is_patch'] as bool? ?? false,
      ssp: master?['is_ssp'] as bool? ?? false,
      imageUrl: master?['image_url'] as String?,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
    );
  }

  double get pl => (currentValue ?? 0) - (pricePaid ?? 0);
  double get plPct => pricePaid != null && pricePaid! > 0 ? (pl / pricePaid!) * 100 : 0;
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
  });

  double get avgCost => qty > 0 ? totalCost / qty : 0;
  double get pl => totalValue - totalCost;
  double get plPct => totalCost > 0 ? (pl / totalCost) * 100 : 0;

  static List<CardStack> fromCards(List<UserCard> cards) {
    final Map<String, List<UserCard>> groups = {};
    for (final c in cards) {
      final key = '${c.masterCardId}__${c.parallel}__${c.grade}__${c.gradeValue}';
      groups.putIfAbsent(key, () => []).add(c);
    }
    return groups.values.map((group) {
      final first = group.first;
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
      );
    }).toList();
  }
}
