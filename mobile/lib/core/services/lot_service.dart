import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_card.dart';

class LotState {
  final List<UserCard> items;
  final int pct;

  const LotState({this.items = const [], this.pct = 100});

  double get totalValue => items.fold(0.0, (s, c) => s + (c.currentValue ?? 0));
  double get askingPrice => totalValue * pct / 100;
  Set<String> get itemIds => items.map((c) => c.id).toSet();

  LotState copyWith({List<UserCard>? items, int? pct}) =>
      LotState(items: items ?? this.items, pct: pct ?? this.pct);
}

class LotNotifier extends Notifier<LotState> {
  @override
  LotState build() => const LotState();

  bool isInLot(String id) => state.itemIds.contains(id);

  void toggle(UserCard card) {
    if (isInLot(card.id)) {
      state = state.copyWith(items: state.items.where((c) => c.id != card.id).toList());
    } else {
      state = state.copyWith(items: [...state.items, card]);
    }
  }

  void remove(String id) {
    state = state.copyWith(items: state.items.where((c) => c.id != id).toList());
  }

  void setPct(int pct) {
    state = state.copyWith(pct: pct.clamp(50, 150));
  }

  void clear() {
    state = const LotState();
  }
}

final lotProvider = NotifierProvider<LotNotifier, LotState>(LotNotifier.new);
