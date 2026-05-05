import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import '../../../core/theme/app_theme.dart';
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
                child: AdaptiveTextField(
                  onChanged: onSearchChanged!,
                  placeholder: searchHint,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  prefixIcon: Icon(Icons.search, size: 18, color: colors.onSurface.withValues(alpha: 0.4)),
                  suffixIcon: searchText!.isNotEmpty
                      ? GestureDetector(
                          onTap: onSearchClear!,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.clear, size: 16),
                          ),
                        )
                      : null,
                  cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(context),
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: searchHint == null || searchHint!.isEmpty ? 'Search' : searchHint,
                    hintText: searchHint,
                    hintStyle: TextStyle(color: colors.onSurface.withValues(alpha: 0.4), fontSize: 14),
                    prefixIcon: Icon(Icons.search, size: 18, color: colors.onSurface.withValues(alpha: 0.4)),
                    suffixIcon: searchText!.isNotEmpty
                        ? GestureDetector(
                            onTap: onSearchClear!,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.clear, size: 16),
                            ),
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
