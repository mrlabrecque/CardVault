import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import '../../../core/widgets/glass_search_field.dart';
import '../../../core/widgets/filter_pill.dart';

class SortMenuOption<T> {
  const SortMenuOption({
    required this.value,
    required this.label,
    this.selected = false,
    this.sfSymbol = 'arrow.up.arrow.down',
  });

  final T value;
  final String label;
  final bool selected;
  final String sfSymbol;
}

class FilterSortActionBar<T> extends StatelessWidget {
  const FilterSortActionBar({
    super.key,
    this.searchController,
    this.searchText,
    this.onSearchChanged,
    this.onSearchClear,
    this.searchHint,
    this.filters = const [],
    this.activeFilters = const {},
    this.onFilterToggle,
    this.sortOptions,
    this.onSortSelected,
    this.actionButton,
  });

  final TextEditingController? searchController;
  final String? searchText;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onSearchClear;
  final String? searchHint;

  final List<String> filters;
  final Set<String> activeFilters;
  final ValueChanged<String>? onFilterToggle;

  final List<SortMenuOption<T>>? sortOptions;
  final ValueChanged<T>? onSortSelected;
  final Widget? actionButton;

  bool get _showsSearch =>
      searchController != null || (searchText != null && onSearchChanged != null);

  @override
  Widget build(BuildContext context) {
    final adaptiveSortItems = sortOptions
        ?.map<AdaptivePopupMenuEntry>(
          (opt) => AdaptivePopupMenuItem<T>(
            value: opt.value,
            label: opt.selected ? '✓ ${opt.label}' : opt.label,
            icon: opt.sfSymbol,
          ),
        )
        .toList();

    return Column(
      children: [
        if (_showsSearch) ...[
          Row(
            children: [
              Expanded(
                child: GlassSearchField(
                  controller: searchController,
                  hint: searchHint ?? 'Search',
                  onChanged: onSearchChanged!,
                  onClear: onSearchClear,
                ),
              ),
              if (adaptiveSortItems != null && onSortSelected != null) ...[
                const SizedBox(width: 6),
                AdaptivePopupMenuButton.icon<T>(
                  icon: 'arrow.up.arrow.down',
                  items: adaptiveSortItems,
                  onSelected: (_, entry) {
                    final value = entry.value;
                    if (value == null) return;
                    onSortSelected!(value);
                  },
                ),
              ],
            ],
          ),
        ] else if (adaptiveSortItems != null && onSortSelected != null) ...[
          Align(
            alignment: Alignment.centerRight,
            child: AdaptivePopupMenuButton.icon<T>(
              icon: 'arrow.up.arrow.down',
              items: adaptiveSortItems,
              onSelected: (_, entry) {
                final value = entry.value;
                if (value == null) return;
                onSortSelected!(value);
              },
            ),
          ),
        ],

        if (filters.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final f in filters)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterPill(
                              label: f,
                              isActive: activeFilters.contains(f),
                              onTap: () => onFilterToggle?.call(f),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (actionButton != null) ...[
                  const SizedBox(width: 8),
                  actionButton!,
                ],
              ],
            ),
          ),
      ],
    );
  }
}
