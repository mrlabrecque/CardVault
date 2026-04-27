import 'package:flutter/material.dart';

/// A reusable layout with a fixed header, sticky sub-header, and scrollable content.
///
/// Structure:
/// - header: Fixed at the top (outside scroll)
/// - subHeader: Sticky below header (stays visible during scroll)
/// - label: Info text below sub-header (optional)
/// - body: Scrollable content
class StickySubHeaderLayout extends StatelessWidget {
  const StickySubHeaderLayout({
    super.key,
    required this.header,
    required this.subHeader,
    required this.body,
    this.label,
    this.headerPadding = const EdgeInsets.fromLTRB(16, 8, 16, 0),
    this.subHeaderPadding = const EdgeInsets.fromLTRB(16, 0, 16, 0),
    this.labelPadding = const EdgeInsets.fromLTRB(16, 6, 16, 0),
    this.bodyTopPadding = 0,
    this.backgroundColor = const Color(0xFFF9FAFB),
    this.useScaffold = true,
  });

  final Widget header;
  final Widget subHeader;
  final Widget body;
  final Widget? label;
  final EdgeInsets headerPadding;
  final EdgeInsets subHeaderPadding;
  final EdgeInsets labelPadding;
  final double bodyTopPadding;
  final Color backgroundColor;
  final bool useScaffold;

  @override
  Widget build(BuildContext context) {
    final column = Column(
      children: [
        // Fixed header
        Padding(
          padding: headerPadding,
          child: header,
        ),
        // Sticky sub-header
        Padding(
          padding: subHeaderPadding,
          child: subHeader,
        ),
        // Optional label/info row
        if (label != null)
          Padding(
            padding: labelPadding,
            child: label!,
          ),
        // Scrollable body
        Expanded(
          child: bodyTopPadding > 0
              ? Padding(
                  padding: EdgeInsets.only(top: bodyTopPadding),
                  child: body,
                )
              : body,
        ),
      ],
    );

    return useScaffold
        ? Scaffold(
            backgroundColor: backgroundColor,
            body: column,
          )
        : column;
  }
}
