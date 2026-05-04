import 'package:flutter/material.dart';
import '../../../core/widgets/filter_pill.dart';

typedef SortMenuBuilder<T> = List<PopupMenuItem<T>> Function(BuildContext);

class FilterSortActionBar<T> extends StatelessWidget {
  const FilterSortActionBar({
    super.key,
    this.searchText,
    this.onSearchChanged,
    this.onSearchClear,
    this.searchHint,
    this.filters = const [],
    this.activeFilters = const {},
    this.onFilterToggle,
    this.sortMenuBuilder,
    this.onSortSelected,
    this.actionButton,
  });

  final String? searchText;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onSearchClear;
  final String? searchHint;

  final List<String> filters;
  final Set<String> activeFilters;
  final ValueChanged<String>? onFilterToggle;

  final SortMenuBuilder<T>? sortMenuBuilder;
  final ValueChanged<T>? onSortSelected;
  final Widget? actionButton;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Row 1: Search + Sort (only if search is enabled)
        if (searchText != null) ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: onSearchChanged!,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: searchHint,
                    hintStyle: TextStyle(color: colors.outline, fontSize: 14),
                    prefixIcon: Icon(Icons.search, size: 18, color: colors.outline),
                    suffixIcon: searchText!.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: onSearchClear!,
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.outline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.primary.withValues(alpha: 0.4)),
                    ),
                  ),
                ),
              ),
              if (sortMenuBuilder != null) ...[
                const SizedBox(width: 6),
                PopupMenuButton<T>(
                  icon: const Icon(Icons.sort),
                  itemBuilder: sortMenuBuilder!,
                  onSelected: onSortSelected!,
                ),
              ],
            ],
          ),
        ] else if (sortMenuBuilder != null) ...[
          // If no search but sort is enabled, just show sort button
          Align(
            alignment: Alignment.centerRight,
            child: PopupMenuButton<T>(
              icon: const Icon(Icons.sort),
              itemBuilder: sortMenuBuilder!,
              onSelected: onSortSelected!,
            ),
          ),
        ],

        // Row 2: Filters + Action
        if (filters.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 8),
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
