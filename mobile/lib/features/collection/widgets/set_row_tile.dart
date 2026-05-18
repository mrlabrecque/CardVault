import 'package:cached_network_image/cached_network_image.dart';
import 'package:card_vault/core/utils/platform_utils.dart';
import 'package:card_vault/core/widgets/adaptive_list_card.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/models/user_card.dart';
import '../../../core/utils/currency_format.dart';

class SetRowTile extends StatefulWidget {
  const SetRowTile({
    super.key,
    required this.row,
    this.onOpenChecklist,
  });

  final SetRow row;
  final void Function({required String parallelName})? onOpenChecklist;

  @override
  State<SetRowTile> createState() => _SetRowTileState();
}

class _SetRowTileState extends State<SetRowTile> {
  bool _expanded = false;

  String get _sportEmoji => switch ((widget.row.sport ?? '').toLowerCase()) {
    'basketball' => '🏀',
    'baseball'   => '⚾',
    'football'   => '🏈',
    'hockey'     => '🏒',
    'soccer'     => '⚽',
    _            => '🏀',
  };

  Color _progressColor(double pct) =>
      pct >= 100 ? Colors.green : const Color(0xFF800020);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final row = widget.row;
    final hasMultipleParallels = row.parallels.length > 1;

    final body = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 60,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: row.imageUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: CachedNetworkImage(
                          imageUrl: row.imageUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => Center(child: Text(_sportEmoji, style: const TextStyle(fontSize: 20))),
                        ),
                      )
                    : Center(child: Text(_sportEmoji, style: const TextStyle(fontSize: 20))),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (row.releaseName != null)
                      Text(
                        [if (row.year != null) '${row.year}', row.releaseName!].join(' '),
                        style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.55)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      row.setName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasMultipleParallels)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('×${row.parallels.length} parallels', style: TextStyle(fontSize: 10, color: colors.primary, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatUsd(row.totalValue), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: colors.onSurface)),
                  Text('${row.ownedCount}/${row.cardCount}', style: TextStyle(fontSize: 11, color: colors.onSurface.withValues(alpha: 0.5))),
                  if (hasMultipleParallels)
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: colors.onSurface.withValues(alpha: 0.4)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ProgressBar(pct: row.pct, color: _progressColor(row.pct)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${row.pct.toStringAsFixed(1)}% complete', style: TextStyle(fontSize: 11, color: colors.onSurface.withValues(alpha: 0.5))),
              Text('${row.ownedCount} of ${row.cardCount} cards', style: TextStyle(fontSize: 11, color: colors.onSurface.withValues(alpha: 0.5))),
            ],
          ),
        ],
      ),
    );

    final openChecklist = widget.onOpenChecklist;
    final defaultParallel = row.parallels.isNotEmpty ? row.parallels.first.parallelName : 'Base';

    Widget header = body;
    if (hasMultipleParallels) {
      header = isIOS
          ? CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: () => setState(() => _expanded = !_expanded),
              child: body,
            )
          : InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(12),
              child: body,
            );
    } else if (openChecklist != null) {
      header = _tappable(
        onTap: () => openChecklist(parallelName: defaultParallel),
        child: body,
      );
    }

    return AdaptiveListCard(
      child: Column(
        children: [
          header,
          if (_expanded && hasMultipleParallels) ...[
            Divider(height: 1, color: colors.outlineVariant),
            ...row.parallels.map(
              (p) => _ParallelRow(
                parallel: p,
                progressColor: _progressColor(p.pct),
                onTap: openChecklist != null
                    ? () => openChecklist(parallelName: p.parallelName)
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tappable({required VoidCallback onTap, required Widget child}) {
    if (isIOS) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: onTap,
        child: child,
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: child,
    );
  }
}

class _ParallelRow extends StatelessWidget {
  const _ParallelRow({
    required this.parallel,
    required this.progressColor,
    this.onTap,
  });
  final SetParallelRow parallel;
  final Color progressColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(parallel.parallelName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
              Text(formatUsd(parallel.totalValue), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('${parallel.ownedCount}/${parallel.cardCount}', style: TextStyle(fontSize: 11, color: colors.onSurface.withValues(alpha: 0.5))),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 16, color: colors.onSurface.withValues(alpha: 0.35)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          _ProgressBar(pct: parallel.pct, color: progressColor, height: 4),
        ],
      ),
    );

    if (onTap == null) return content;

    if (isIOS) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: onTap,
        child: content,
      );
    }
    return InkWell(onTap: onTap, child: content);
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.pct, required this.color, this.height = 6});
  final double pct;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: (pct / 100).clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: colors.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}
