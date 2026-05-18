import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utils/platform_utils.dart';
import 'tab_bar_glass_surface.dart';

/// Search pill with tab-bar-matched glass (Flutter backdrop blur + ultra-thin tint).
class GlassSearchField extends StatefulWidget {
  const GlassSearchField({
    super.key,
    this.controller,
    required this.hint,
    required this.onChanged,
    this.onClear,
    this.focusNode,
    this.autofocus = false,
    this.onSubmitted,
    this.textInputAction,
  });

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  static const double pillHeight = 44;
  static const double pillRadius = 22;

  @override
  State<GlassSearchField> createState() => _GlassSearchFieldState();
}

class _GlassSearchFieldState extends State<GlassSearchField> {
  @override
  Widget build(BuildContext context) {
    if (widget.controller != null) {
      return ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.controller!,
        builder: (context, value, _) => _buildPill(context, value.text),
      );
    }
    return _buildPill(context, '');
  }

  Widget _buildPill(BuildContext context, String displayText) {
    final colors = Theme.of(context).colorScheme;
    final showClear = displayText.isNotEmpty && widget.onClear != null;
    final borderRadius = BorderRadius.circular(GlassSearchField.pillRadius);

    final searchIcon = Icon(
      isIOS ? CupertinoIcons.search : Icons.search_rounded,
      size: 17,
      color: colors.onSurface.withValues(alpha: 0.45),
    );

    final clearControl = showClear
        ? GestureDetector(
            onTap: widget.onClear,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                isIOS ? CupertinoIcons.xmark_circle_fill : Icons.cancel,
                size: 18,
                color: colors.onSurface.withValues(alpha: 0.35),
              ),
            ),
          )
        : const SizedBox(width: 8);

    final field = AdaptiveTextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      placeholder: widget.hint,
      style: TextStyle(
        fontSize: isIOS ? 17 : 15,
        color: colors.onSurface,
        letterSpacing: isIOS ? -0.2 : 0,
      ),
      padding: const EdgeInsets.symmetric(vertical: 2),
      prefix: Padding(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: searchIcon,
      ),
      suffix: clearControl,
      cupertinoDecoration: const BoxDecoration(color: Color(0x00000000)),
      decoration: const InputDecoration(
        filled: true,
        fillColor: Colors.transparent,
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: 12),
      ),
    );

    return TabBarGlassSurface(
      borderRadius: borderRadius,
      height: GlassSearchField.pillHeight,
      child: Align(
        alignment: Alignment.center,
        child: field,
      ),
    );
  }
}
