import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/cards_service.dart';
import '../../core/models/user_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final cardsAsync = ref.watch(userCardsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: cardsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (cards) {
          final stacks = CardStack.fromCards(cards);
          final totalValue = cards.fold(0.0, (s, c) => s + (c.currentValue ?? 0));
          final totalCost  = cards.fold(0.0, (s, c) => s + (c.pricePaid ?? 0));
          final pl = totalValue - totalCost;
          final plPct = totalCost > 0 ? (pl / totalCost) * 100 : 0.0;
          final plColor = pl >= 0 ? Colors.green : colors.error;

          final sportCounts = <String, int>{};
          for (final c in cards) {
            sportCounts[c.sport] = (sportCounts[c.sport] ?? 0) + 1;
          }

          final topCards = [...stacks]..sort((a, b) => b.totalValue.compareTo(a.totalValue));

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(userCardsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
              children: [
                _StatRow(children: [
                  _StatCard(label: 'Cards', value: '${cards.length}', icon: Icons.style),
                  _StatCard(label: 'Value', value: '\$${totalValue.toStringAsFixed(2)}', icon: Icons.attach_money),
                ]),
                const SizedBox(height: 8),
                _StatRow(children: [
                  _StatCard(label: 'Cost Basis', value: '\$${totalCost.toStringAsFixed(2)}', icon: Icons.receipt),
                  _StatCard(
                    label: 'P/L',
                    value: '${pl >= 0 ? '+' : ''}\$${pl.toStringAsFixed(2)} (${plPct.toStringAsFixed(1)}%)',
                    icon: pl >= 0 ? Icons.trending_up : Icons.trending_down,
                    valueColor: plColor,
                  ),
                ]),
                const SizedBox(height: 20),
                Text('By Sport', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...sportCounts.entries.map((e) {
                  final pct = cards.isNotEmpty ? e.value / cards.length : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(e.key.isEmpty ? 'Unknown' : e.key),
                            Text('${e.value} (${(pct * 100).toStringAsFixed(0)}%)'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(value: pct, minHeight: 8, backgroundColor: colors.surfaceContainerHighest),
                        ),
                      ],
                    ),
                  );
                }),
                if (topCards.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Top Cards by Value', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...topCards.take(5).map((s) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.player, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${s.year ?? ''} ${s.set ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text('\$${s.totalValue.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  )),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
        children: children.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: c))).toList(),
      );
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, this.valueColor});
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: colors.primary),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: valueColor)),
            Text(label, style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.6))),
          ],
        ),
      ),
    );
  }
}
