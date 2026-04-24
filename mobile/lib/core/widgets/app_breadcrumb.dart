import 'package:flutter/material.dart';

/// Compact sub-page header with up to 3 levels: [grandparent ›] [parent ›] current.
/// Navigation is text-only — no back arrow. Ancestor labels are tappable.
/// Adds status-bar safe area automatically.
class AppBreadcrumb extends StatelessWidget {
  const AppBreadcrumb({
    super.key,
    this.grandparent,
    this.onGrandparentBack,
    this.parent,
    required this.current,
    this.onBack,
    this.trailing,
  });

  final String? grandparent;
  final VoidCallback? onGrandparentBack;
  final String? parent;
  final String current;

  /// Tapped on parent label. Defaults to [Navigator.pop] when null.
  final VoidCallback? onBack;

  /// Optional widget placed at the trailing end (e.g. delete or info button).
  final Widget? trailing;

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

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final back = onBack ?? () => Navigator.of(context).pop();
    return Container(
      padding: EdgeInsets.fromLTRB(16, top + 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          // Grandparent level
          if (grandparent != null) ...[
            GestureDetector(
              onTap: onGrandparentBack,
              child: Text(grandparent!, style: _ancestorStyle),
            ),
            _sep,
          ],
          // Parent level
          if (parent != null) ...[
            GestureDetector(
              onTap: back,
              child: Text(parent!, style: _ancestorStyle),
            ),
            _sep,
          ],
          // Current level
          Expanded(
            child: Text(current, style: _currentStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
