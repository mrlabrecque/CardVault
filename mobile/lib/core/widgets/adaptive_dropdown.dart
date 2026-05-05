import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/platform_utils.dart';

class AdaptiveDropdown<T> extends StatefulWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? labelText;
  final String? hint;
  final InputDecoration? decoration;

  const AdaptiveDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelText,
    this.hint,
    this.decoration,
  });

  @override
  State<AdaptiveDropdown<T>> createState() => _AdaptiveDropdownState<T>();
}

class _AdaptiveDropdownState<T> extends State<AdaptiveDropdown<T>> {
  @override
  Widget build(BuildContext context) {
    if (isIOS) {
      return _buildIOSDropdown();
    } else {
      return _buildAndroidDropdown();
    }
  }

  Widget _buildIOSDropdown() {
    final colors = Theme.of(context).colorScheme;
    final effectiveLabel = widget.labelText ?? widget.decoration?.labelText;
    final effectiveHint = widget.hint ?? widget.decoration?.hintText ?? 'Select...';
    final selectedIndex = widget.items.indexWhere((item) => item.value == widget.value);
    final displayText = selectedIndex >= 0
        ? (widget.items[selectedIndex].child is Text
            ? (widget.items[selectedIndex].child as Text).data ?? ''
            : widget.items[selectedIndex].child.toString())
        : effectiveHint;

    return GestureDetector(
      onTap: () => _showIOSPicker(),
      child: Container(
        decoration: AppTheme.cupertinoTextFieldDecoration(context),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.black87),
          child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (effectiveLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        effectiveLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  Text(
                    displayText,
                    style: TextStyle(
                      fontSize: 14,
                      color: selectedIndex >= 0
                          ? colors.onSurface
                          : colors.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_down,
              size: 18,
              color: colors.onSurface.withValues(alpha: 0.4),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildAndroidDropdown() {
    return DropdownButtonFormField<T>(
      initialValue: widget.value,
      items: widget.items,
      onChanged: widget.onChanged,
      decoration: widget.decoration ??
          InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
    );
  }

  void _showIOSPicker() {
    showCupertinoModalPopup<T>(
      context: context,
      builder: (BuildContext context) {
        int selectedIndex = widget.items.indexWhere((item) => item.value == widget.value);
        if (selectedIndex < 0) selectedIndex = 0;

        return Container(
          height: 250,
          color: CupertinoColors.systemBackground.resolveFrom(context),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.black87),
            child: Column(
              children: [
              // Header with Done button
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: CupertinoColors.separator.resolveFrom(context),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.labelText ?? 'Select',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              // Picker
              Expanded(
                child: CupertinoPicker(
                  itemExtent: 40,
                  scrollController: FixedExtentScrollController(initialItem: selectedIndex),
                  onSelectedItemChanged: (index) {
                    widget.onChanged(widget.items[index].value);
                  },
                  children: widget.items.map((item) {
                    return Center(child: item.child);
                  }).toList(),
                ),
              ),
            ],
            ),
          ),
        );
      },
    );
  }
}
