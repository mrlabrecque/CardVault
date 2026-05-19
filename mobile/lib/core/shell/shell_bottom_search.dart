import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shell tab indices that use the bottom search pill for in-tab filtering.
const shellSearchTabIndices = <int>{1, 3}; // Catalog, Collection

bool shellTabSupportsSearch(int tabIndex) =>
    shellSearchTabIndices.contains(tabIndex);

bool shellLocationSupportsSearch(String location) =>
    location.startsWith('/catalog') ||
    location.startsWith('/collection') ||
    location.startsWith('/wishlist');

String shellSearchHintForTab(int tabIndex) => switch (tabIndex) {
      1 => 'Search releases, sets, cards…',
      3 => 'Search player, set, sport…',
      _ => 'Search catalog…',
    };

String shellSearchHintForLocation(String location) {
  if (location.startsWith('/catalog')) {
    return 'Search releases, sets, cards…';
  }
  if (location.startsWith('/collection')) {
    return 'Search player, set, sport…';
  }
  if (location.startsWith('/wishlist')) {
    return 'Search player, set, parallel…';
  }
  return shellSearchHintForTab(0);
}

class ShellBottomSearchState {
  const ShellBottomSearchState({
    this.isActive = false,
    this.query = '',
  });

  final bool isActive;
  final String query;

  ShellBottomSearchState copyWith({bool? isActive, String? query}) {
    return ShellBottomSearchState(
      isActive: isActive ?? this.isActive,
      query: query ?? this.query,
    );
  }
}

/// Shared bottom-bar search field state (controller owned here for the glass pill).
class ShellBottomSearch extends Notifier<ShellBottomSearchState> {
  late final TextEditingController controller;
  late final FocusNode focusNode;

  @override
  ShellBottomSearchState build() {
    controller = TextEditingController();
    focusNode = FocusNode();
    ref.onDispose(() {
      controller.dispose();
      focusNode.dispose();
    });
    controller.addListener(() {
      final text = controller.text;
      if (text != state.query) {
        state = state.copyWith(query: text);
      }
    });
    return const ShellBottomSearchState();
  }

  void setActive(bool active) {
    state = state.copyWith(isActive: active);
    if (!active) {
      controller.clear();
      focusNode.unfocus();
    }
  }

  void clearQuery() {
    if (controller.text.isEmpty) return;
    controller.clear();
    state = state.copyWith(query: '');
  }
}

final shellBottomSearchProvider =
    NotifierProvider<ShellBottomSearch, ShellBottomSearchState>(
  ShellBottomSearch.new,
);
