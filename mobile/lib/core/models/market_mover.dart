class MarketMover {
  final String topPlayerId;
  final String playerName;
  final String sport;
  final double currentAvg;
  final double previousAvg;
  final int currentVolume;
  final int previousVolume;
  final double priceChangePct; // (current - previous) / previous * 100
  final double volumeChangePct;

  MarketMover({
    required this.topPlayerId,
    required this.playerName,
    required this.sport,
    required this.currentAvg,
    required this.previousAvg,
    required this.currentVolume,
    required this.previousVolume,
    required this.priceChangePct,
    required this.volumeChangePct,
  });

  // Helper to determine if trending up or down
  bool get isTrendingUp => priceChangePct > 0;
  bool get isTrendingDown => priceChangePct < 0;
}

class MarketMoversData {
  final List<MarketMover> hot; // sorted priceChangePct DESC
  final List<MarketMover> cold; // sorted priceChangePct ASC
  final DateTime? lastUpdated;

  MarketMoversData({
    required this.hot,
    required this.cold,
    this.lastUpdated,
  });
}
