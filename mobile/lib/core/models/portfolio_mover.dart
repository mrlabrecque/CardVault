class PortfolioMover {
  final String topPlayerId;
  final String playerName;
  final String sport;
  /// Optional second line (e.g. set / parallel from top movers).
  final String? cardDescription;
  final double currentAvg;
  final double previousAvg;
  final int currentVolume;
  final int previousVolume;
  final double priceChangePct;
  final double volumeChangePct;

  PortfolioMover({
    required this.topPlayerId,
    required this.playerName,
    required this.sport,
    this.cardDescription,
    required this.currentAvg,
    required this.previousAvg,
    required this.currentVolume,
    required this.previousVolume,
    required this.priceChangePct,
    required this.volumeChangePct,
  });

  bool get isTrendingUp => priceChangePct > 0;
  bool get isTrendingDown => priceChangePct < 0;
}

class PortfolioMoversData {
  final List<PortfolioMover> hot;
  final List<PortfolioMover> cold;
  final DateTime? lastUpdated;

  PortfolioMoversData({
    required this.hot,
    required this.cold,
    this.lastUpdated,
  });
}
