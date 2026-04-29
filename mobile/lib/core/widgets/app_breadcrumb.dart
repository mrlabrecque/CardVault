import 'package:flutter/material.dart';

/// Multi-level breadcrumb with flexible depth. All ancestor labels are tappable
/// for direct navigation. Navigation is text-only — no back arrow.
/// Adds status-bar safe area automatically.
class AppBreadcrumb extends StatelessWidget {
  const AppBreadcrumb({
    super.key,
    this.grandparent,
    this.onGrandparentBack,
    this.parent,
    this.current,
    this.onBack,
    this.trailing,
    this.items,
  });

  final String? grandparent;
  final VoidCallback? onGrandparentBack;
  final String? parent;
  final String? current;
  final VoidCallback? onBack;
  final Widget? trailing;
  final List<BreadcrumbItem>? items;

  static const _ancestorStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: Color(0xFF9CA3AF),
  );

  static const _currentStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: Color(0xFF374151),
  );

  static const _sep = Padding(
    padding: EdgeInsets.symmetric(horizontal: 4),
    child: Icon(Icons.chevron_right, size: 14, color: Color(0xFFD1D5DB)),
  );

  List<BreadcrumbItem> _buildItems(BuildContext context) {
    if (items != null) return items!;

    final builtItems = <BreadcrumbItem>[];
    if (grandparent != null) {
      builtItems.add(BreadcrumbItem(label: grandparent!, onTap: onGrandparentBack));
    }
    if (parent != null) {
      builtItems.add(BreadcrumbItem(
        label: parent!,
        onTap: onBack ?? () => Navigator.of(context).pop(),
      ));
    }
    if (current != null) {
      builtItems.add(BreadcrumbItem(label: current!));
    }
    return builtItems;
  }

  @override
  Widget build(BuildContext context) {
    final breadcrumbItems = _buildItems(context);
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: DefaultTextStyle(
        style: TextStyle(color: Colors.black87, fontFamily: fontFamily),
        child: Row(
        children: [
          Flexible(
            child: Row(
              children: [
                for (int i = 0; i < breadcrumbItems.length; i++) ...[
                  if (i > 0) _sep,
                  if (i < breadcrumbItems.length - 1)
                    Flexible(
                      fit: FlexFit.loose,
                      child: GestureDetector(
                        onTap: breadcrumbItems[i].onTap,
                        child: Text(
                          breadcrumbItems[i].label,
                          style: _ancestorStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                  else
                    Flexible(
                      fit: FlexFit.loose,
                      child: Text(
                        breadcrumbItems[i].label,
                        style: _currentStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (trailing case final t?) t,
        ],
        ),
      ),
    );
  }
}

class BreadcrumbItem {
  const BreadcrumbItem({
    required this.label,
    this.onTap,
  });

  final String label;
  final VoidCallback? onTap;
}
