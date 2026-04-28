import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/user_card.dart';

class SetRowTile extends StatefulWidget {
  const SetRowTile({super.key, required this.row});
  final SetRow row;

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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: hasMultipleParallels ? () => setState(() => _expanded = !_expanded) : null,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Image / emoji
                      Container(
                        width: 44,
                        height: 60,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.12),
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
                      // Info
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
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
                      // Value + chevron
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('\$${row.totalValue.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          Text('${row.ownedCount}/${row.cardCount}', style: TextStyle(fontSize: 11, color: colors.onSurface.withValues(alpha: 0.5))),
                          if (hasMultipleParallels)
                            Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: colors.onSurface.withValues(alpha: 0.4)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Progress bar
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
            ),
          ),
          // Expanded parallels
          if (_expanded && hasMultipleParallels) ...[
            const Divider(height: 1),
            ...row.parallels.map((p) => _ParallelRow(parallel: p, progressColor: _progressColor(p.pct))),
          ],
        ],
      ),
    );
  }
}

class _ParallelRow extends StatelessWidget {
  const _ParallelRow({required this.parallel, required this.progressColor});
  final SetParallelRow parallel;
  final Color progressColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(parallel.parallelName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
              Text('\$${parallel.totalValue.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('${parallel.ownedCount}/${parallel.cardCount}', style: TextStyle(fontSize: 11, color: colors.onSurface.withValues(alpha: 0.5))),
            ],
          ),
          const SizedBox(height: 6),
          _ProgressBar(pct: parallel.pct, color: progressColor, height: 4),
        ],
      ),
    );
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
