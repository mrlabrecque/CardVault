import 'package:flutter/material.dart';

typedef SortMenuBuilder<T> = List<PopupMenuItem<T>> Function(BuildContext);

class FilterSortActionBar<T> extends StatelessWidget {
  const FilterSortActionBar({
    super.key,
    required this.searchText,
    required this.onSearchChanged,
    required this.onSearchClear,
    required this.searchHint,
    this.filters = const [],
    this.activeFilters = const {},
    this.onFilterToggle,
    this.sortMenuBuilder,
    this.onSortSelected,
    required this.actionButton,
  });

  final String searchText;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchClear;
  final String searchHint;

  final List<String> filters;
  final Set<String> activeFilters;
  final ValueChanged<String>? onFilterToggle;

  final SortMenuBuilder<T>? sortMenuBuilder;
  final ValueChanged<T>? onSortSelected;
  final Widget actionButton;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Row 1: Search + Sort
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: onSearchChanged,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: searchHint,
                  hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF9CA3AF)),
                  suffixIcon: searchText.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: onSearchClear,
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
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

        // Row 2: Filters + Action
        if (filters.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final f in filters)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(f),
                              selected: activeFilters.contains(f),
                              onSelected: (_) => onFilterToggle?.call(f),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                actionButton,
              ],
            ),
          ),
      ],
    );
  }
}
