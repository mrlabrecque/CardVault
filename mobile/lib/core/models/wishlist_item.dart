class WishlistItem {
  final String id;
  final Map<String, dynamic> cardDetails;
  final double? targetPrice;
  final String alertStatus;
  final DateTime? createdAt;

  const WishlistItem({
    required this.id,
    required this.cardDetails,
    this.targetPrice,
    required this.alertStatus,
    this.createdAt,
  });

  String get player => cardDetails['player'] as String? ?? '';
  String get description => cardDetails['description'] as String? ?? cardDetails['set'] as String? ?? '';

  factory WishlistItem.fromJson(Map<String, dynamic> json) => WishlistItem(
        id: json['id'] as String,
        cardDetails: json['card_details'] as Map<String, dynamic>? ?? {},
        targetPrice: (json['target_price'] as num?)?.toDouble(),
        alertStatus: json['alert_status'] as String? ?? 'inactive',
        createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
      );
}
