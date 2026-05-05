import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import '../../core/services/cards_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/adaptive_dropdown.dart';
import '../../core/widgets/modal_sheet_scaffold.dart';
import 'wishlist_card_preview.dart';

const _graders = ['PSA', 'BGS', 'SGC', 'CGC', 'CSG'];

class CardSheet extends StatefulWidget {
  const CardSheet({
    super.key,
    required this.title,
    required this.card,
    this.year,
    required this.setName,
    required this.releaseName,
    required this.onSave,
    this.showParallel = false,
    this.parallels = const [],
    this.selectedParallel,
    this.onParallelChanged,
    this.showPricePaid = false,
    this.pricePaidCtrl,
    this.showSerialNumber = false,
    this.serialNumberCtrl,
    this.showWatchWords = false,
    this.watchWordsCtrl,
    this.showTargetPrice = false,
    this.targetPriceCtrl,
    this.showGraded = true,
    this.isGraded = false,
    this.grader = 'PSA',
    this.gradeValueCtrl,
    this.onGradedChanged,
    this.onGraderChanged,
  });

  final String title;
  final MasterCard? card;
  final int? year;
  final String? setName;
  final String? releaseName;
  final Future<String?> Function(Map<String, dynamic>) onSave;

  // Parallel section
  final bool showParallel;
  final List<SetParallel> parallels;
  final SetParallel? selectedParallel;
  final void Function(SetParallel?)? onParallelChanged;

  // Price Paid section
  final bool showPricePaid;
  final TextEditingController? pricePaidCtrl;

  // Serial Number section
  final bool showSerialNumber;
  final TextEditingController? serialNumberCtrl;

  // Watch Words section
  final bool showWatchWords;
  final TextEditingController? watchWordsCtrl;

  // Target Price section
  final bool showTargetPrice;
  final TextEditingController? targetPriceCtrl;

  // Graded section
  final bool showGraded;
  final bool isGraded;
  final String grader;
  final TextEditingController? gradeValueCtrl;
  final void Function(bool)? onGradedChanged;
  final void Function(String?)? onGraderChanged;

  @override
  State<CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends State<CardSheet> {
  final List<String> _watchWords = [];
  bool _saving = false;
  String? _error;

  void _addWatchWord() {
    final word = widget.watchWordsCtrl?.text.trim() ?? '';
    if (word.isNotEmpty && !_watchWords.contains(word)) {
      setState(() => _watchWords.add(word));
      widget.watchWordsCtrl?.clear();
    }
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      final error = await widget.onSave({});
      if (!mounted) return;
      setState(() => _saving = false);
      if (error != null) {
        setState(() => _error = error);
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() { _saving = false; _error = e.toString(); });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ModalSheetScaffold(
      title: widget.title,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.black87),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: colors.error.withValues(alpha: 0.1),
                          border: Border.all(color: colors.error.withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(children: [
                          Icon(Icons.error_outline, size: 14, color: colors.error),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!, style: TextStyle(fontSize: 13, color: colors.error))),
                        ]),
                      ),
                      const SizedBox(height: 16),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: WishlistCardPreview(
                        card: widget.card,
                        setName: widget.setName,
                        releaseName: widget.releaseName,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (widget.showParallel) ...[
                      if (widget.parallels.isNotEmpty)
                        AdaptiveDropdown<SetParallel?>(
                          value: widget.selectedParallel,
                          decoration: InputDecoration(
                            labelText: 'Parallel',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Base')),
                            ...widget.parallels.map((p) => DropdownMenuItem(value: p, child: Text(p.name))),
                          ],
                          onChanged: (v) => widget.onParallelChanged?.call(v),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No parallels for this set',
                            style: TextStyle(fontSize: 13, color: colors.onSurface.withValues(alpha: 0.6)),
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                    if (widget.showPricePaid) ...[
                      AdaptiveTextField(
                        controller: widget.pricePaidCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        placeholder: '\$0.00',
                        cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(context),
                        decoration: InputDecoration(
                          labelText: 'Price Paid',
                          hintText: '\$0.00',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (widget.showSerialNumber) ...[
                      AdaptiveTextField(
                        controller: widget.serialNumberCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        placeholder: 'e.g., 45 (from 45/99)',
                        cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(context),
                        decoration: InputDecoration(
                          labelText: 'Serial #',
                          hintText: 'e.g., 45 (from 45/99)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (widget.showWatchWords) ...[
                      AdaptiveTextField(
                        controller: widget.watchWordsCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        placeholder: 'e.g. draft picks',
                        cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(context),
                        decoration: InputDecoration(
                          labelText: 'Excluded Words',
                          hintText: 'e.g. draft picks',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _addWatchWord(),
                      ),
                      if (_watchWords.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final word in _watchWords)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colors.error.withValues(alpha: 0.1),
                                    border: Border.all(color: colors.error.withValues(alpha: 0.3)),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text(word, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.error)),
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () => setState(() => _watchWords.remove(word)),
                                      child: Icon(Icons.close, size: 12, color: colors.error.withValues(alpha: 0.6)),
                                    ),
                                  ]),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                    if (widget.showTargetPrice) ...[
                      AdaptiveTextField(
                        controller: widget.targetPriceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        placeholder: '\$0.00',
                        cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(context),
                        decoration: InputDecoration(
                          labelText: 'Target Price',
                          hintText: '\$0.00',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (widget.showGraded) ...[
                      Row(
                        children: [
                          const Expanded(child: Text('Graded?')),
                          AdaptiveSwitch(
                            value: widget.isGraded,
                            onChanged: widget.onGradedChanged,
                          ),
                        ],
                      ),
                      if (widget.isGraded) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: AdaptiveDropdown<String>(
                                value: widget.grader,
                                decoration: InputDecoration(
                                  labelText: 'Grader',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  isDense: true,
                                ),
                                items: _graders.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                                onChanged: (v) => widget.onGraderChanged?.call(v),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: AdaptiveTextField(
                                controller: widget.gradeValueCtrl,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                placeholder: '10',
                                cupertinoDecoration: AppTheme.cupertinoTextFieldDecoration(context),
                                decoration: InputDecoration(
                                  labelText: 'Grade',
                                  hintText: '10',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
            const SizedBox(height: 12),
            Divider(height: 1, color: colors.outline.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: AdaptiveButton.child(
                onPressed: _saving ? null : _save,
                style: AdaptiveButtonStyle.filled,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
