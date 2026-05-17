import '../../core/models/user_card.dart';
import 'card_detail_screen.dart';

/// Collection copy detail — see [CardDetailScreen.owned].
class ItemDetailScreen extends CardDetailScreen {
  const ItemDetailScreen({super.key, required UserCard card}) : super.owned(card: card);
}
