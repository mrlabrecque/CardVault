import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/cards_service.dart';
import '../../core/models/user_card.dart';

const _burgundy = Color(0xFF800020);

const _sportColors = {
  'Basketball': Color(0xFF10b981),
  'Football':   Color(0xFF3b82f6),
  'Baseball':   Color(0xFFf59e0b),
  'Soccer':     Color(0xFF8b5cf6),
  'Hockey':     Color(0xFFef4444),
};
const _defaultSportColor = Color(0xFF94a3b8);

typedef _Stat = String; // 'value' | 'pl' | 'cards'
typedef _Chart = String; // 'breakdown' | 'timeline'
typedef _Bottom = String; // 'top-cards' | 'top-players'

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  _Stat _selectedStat = 'value';
  _Chart _chartView = 'breakdown';
  _Bottom _bottomView = 'top-cards';

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(userCardsProvider);

    return Scaffold(
      body: cardsAsync.when(
        loading: () => _buildSkeleton(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (cards) {
          if (cards.isEmpty) return _buildEmpty();
          return _buildContent(cards);
        },
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      children: [
        Row(children: List.generate(3, (_) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _shimmer(height: 96, radius: 16),
          ),
        ))),
        const SizedBox(height: 12),
        _shimmer(height: 280, radius: 16),
        const SizedBox(height: 12),
        _shimmer(height: 220, radius: 16),
      ],
    );
  }

  Widget _shimmer({required double height, double radius = 8}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🃏', style: TextStyle(fontSize: 48)),
          SizedBox(height: 12),
          Text('No cards yet', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.black87)),
          SizedBox(height: 4),
          Text('Add your first card using the + button below.',
              style: TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildContent(List<UserCard> cards) {
    final totalValue = cards.fold(0.0, (s, c) => s + (c.currentValue ?? 0));
    final totalCost  = cards.fold(0.0, (s, c) => s + (c.pricePaid ?? 0));
    final pl = totalValue - totalCost;
    final plPct = totalCost > 0 ? (pl / totalCost) * 100 : null;

    // Sport breakdown data
    final sportValues = <String, double>{};
    final sportCounts = <String, int>{};
    final sportPL = <String, double>{};
    for (final c in cards) {
      final s = c.sport.isEmpty ? 'Other' : c.sport;
      sportValues[s] = (sportValues[s] ?? 0) + (c.currentValue ?? 0);
      sportCounts[s] = (sportCounts[s] ?? 0) + 1;
      sportPL[s] = (sportPL[s] ?? 0) + ((c.currentValue ?? 0) - (c.pricePaid ?? 0));
    }

    final breakdownMap = _selectedStat == 'value' ? sportValues
        : _selectedStat == 'pl' ? sportPL
        : sportCounts.map((k, v) => MapEntry(k, v.toDouble()));
    final breakdownEntries = breakdownMap.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    // Timeline data
    final timelinePoints = _buildTimeline(cards, _selectedStat);

    // Top cards
    final topCards = [...cards]
        .where((c) => (c.currentValue ?? 0) > 0)
        .toList()
      ..sort((a, b) => (b.currentValue ?? 0).compareTo(a.currentValue ?? 0));

    // Top players
    final playerCounts = <String, int>{};
    for (final c in cards) {
      if (c.player.isNotEmpty) playerCounts[c.player] = (playerCounts[c.player] ?? 0) + 1;
    }
    final topPlayers = playerCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final chartTitle = _chartTitle();

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(userCardsProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        children: [
          // ── Stat tiles ──────────────────────────────────────────────────
          Row(children: [
            _StatTile(
              label: 'Total Value',
              value: '\$${totalValue.toStringAsFixed(0)}',
              icon: Icons.account_balance_wallet_outlined,
              iconBg: _burgundy,
              selected: _selectedStat == 'value',
              onTap: () => setState(() => _selectedStat = 'value'),
            ),
            _StatTile(
              label: 'P / L',
              value: '${pl >= 0 ? '+' : ''}\$${pl.toStringAsFixed(0)}',
              subValue: plPct != null
                  ? '${plPct >= 0 ? '+' : ''}${plPct.toStringAsFixed(1)}%'
                  : null,
              icon: Icons.show_chart,
              iconBg: pl >= 0 ? const Color(0xFF10b981) : const Color(0xFFf87171),
              valueColor: pl >= 0 ? const Color(0xFF059669) : const Color(0xFFef4444),
              subValueColor: pl >= 0 ? const Color(0xFF10b981) : const Color(0xFFf87171),
              selected: _selectedStat == 'pl',
              onTap: () => setState(() => _selectedStat = 'pl'),
            ),
            _StatTile(
              label: 'Cards',
              value: '${cards.length}',
              icon: Icons.grid_view,
              iconBg: _burgundy.withValues(alpha: 0.7),
              selected: _selectedStat == 'cards',
              onTap: () => setState(() => _selectedStat = 'cards'),
            ),
          ]),

          const SizedBox(height: 12),

          // ── Chart panel ─────────────────────────────────────────────────
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(chartTitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                    _ToggleButtons(
                      options: const [
                        (Icons.donut_large, 'breakdown'),
                        (Icons.show_chart, 'timeline'),
                      ],
                      selected: _chartView,
                      onSelect: (v) => setState(() => _chartView = v),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_chartView == 'breakdown')
                  breakdownEntries.isEmpty
                      ? const _EmptyChart(message: 'No data yet.')
                      : _DonutChart(entries: breakdownEntries, height: 220)
                else
                  timelinePoints.length < 2
                      ? _EmptyChart(message: timelinePoints.length == 1
                          ? 'Add more cards to see movement over time.'
                          : 'No data yet.')
                      : _LineChart(points: timelinePoints, stat: _selectedStat, height: 200),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Bottom list panel ────────────────────────────────────────────
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _bottomView == 'top-cards' ? 'Top Cards by Value' : 'Top Players by Count',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                    _ToggleButtons(
                      options: const [
                        (Icons.attach_money, 'top-cards'),
                        (Icons.person_outline, 'top-players'),
                      ],
                      selected: _bottomView,
                      onSelect: (v) => setState(() => _bottomView = v),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (_bottomView == 'top-cards')
                  topCards.isEmpty
                      ? const _EmptyChart(message: 'No cards with a current value yet.')
                      : Column(children: [
                          for (int i = 0; i < topCards.take(5).length; i++)
                            _RankedCardRow(
                              rank: i + 1,
                              title: topCards[i].player,
                              subtitle: '${topCards[i].year ?? ''} ${topCards[i].set ?? ''}'.trim(),
                              trailing: '\$${(topCards[i].currentValue ?? 0).toStringAsFixed(0)}',
                              onTap: () => context.go('/collection/card', extra: topCards[i]),
                            ),
                        ])
                else
                  topPlayers.isEmpty
                      ? const _EmptyChart(message: 'No cards in your collection yet.')
                      : Column(children: [
                          for (int i = 0; i < topPlayers.take(5).length; i++)
                            _RankedCardRow(
                              rank: i + 1,
                              title: topPlayers[i].key,
                              trailing: '${topPlayers[i].value} ${topPlayers[i].value == 1 ? 'card' : 'cards'}',
                              onTap: () => context.go('/collection'),
                            ),
                        ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _chartTitle() {
    final statLabel = {'value': 'Value', 'pl': 'P / L', 'cards': 'Cards'}[_selectedStat]!;
    final viewLabel = {'breakdown': 'by Sport', 'timeline': 'Over Time'}[_chartView]!;
    return '$statLabel $viewLabel';
  }

  List<({String label, double value})> _buildTimeline(List<UserCard> cards, String stat) {
    final sorted = cards.where((c) => c.createdAt != null).toList()
      ..sort((a, b) => a.createdAt!.compareTo(b.createdAt!));

    final byDate = <String, double>{};
    for (final c in sorted) {
      final date = c.createdAt!.toIso8601String().substring(0, 10);
      final val = stat == 'cards' ? 1.0
          : stat == 'value' ? (c.currentValue ?? 0)
          : (c.currentValue ?? 0) - (c.pricePaid ?? 0);
      byDate[date] = (byDate[date] ?? 0) + val;
    }

    final dates = byDate.keys.toList()..sort();
    double running = 0;
    return dates.map((d) {
      running += byDate[d]!;
      final dt = DateTime.parse('${d}T12:00:00');
      final label = '${_monthAbbr(dt.month)} ${dt.day}';
      return (label: label, value: double.parse(running.toStringAsFixed(2)));
    }).toList();
  }

  String _monthAbbr(int m) =>
      const ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.subValue,
    required this.icon,
    required this.iconBg,
    this.valueColor,
    this.subValueColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final String? subValue;
  final IconData icon;
  final Color iconBg;
  final Color? valueColor;
  final Color? subValueColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))],
              border: Border.all(
                color: selected ? _burgundy : const Color(0xFFF3F4F6),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: Colors.white, size: 16),
                ),
                const SizedBox(height: 8),
                Text(value,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                        color: valueColor ?? Colors.black87, height: 1),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subValue != null) ...[
                  const SizedBox(height: 2),
                  Text(subValue!,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                          color: subValueColor ?? Colors.grey.shade500)),
                ],
                const SizedBox(height: 2),
                Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade400, height: 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1))],
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: child,
    );
  }
}

class _ToggleButtons extends StatelessWidget {
  const _ToggleButtons({required this.options, required this.selected, required this.onSelect});
  final List<(IconData, String)> options;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < options.length; i++) ...[
            if (i > 0) Container(width: 1, height: 28, color: const Color(0xFFE5E7EB)),
            GestureDetector(
              onTap: () => onSelect(options[i].$2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: selected == options[i].$2 ? _burgundy : Colors.transparent,
                  borderRadius: BorderRadius.horizontal(
                    left: i == 0 ? const Radius.circular(7) : Radius.zero,
                    right: i == options.length - 1 ? const Radius.circular(7) : Radius.zero,
                  ),
                ),
                child: Icon(options[i].$1,
                    size: 14,
                    color: selected == options[i].$2 ? Colors.white : Colors.grey.shade400),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(message, style: TextStyle(fontSize: 12, color: Colors.grey.shade400), textAlign: TextAlign.center),
      ),
    );
  }
}

class _RankedCardRow extends StatelessWidget {
  const _RankedCardRow({
    required this.rank,
    required this.title,
    this.subtitle,
    required this.trailing,
    required this.onTap,
  });
  final int rank;
  final String title;
  final String? subtitle;
  final String trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
              child: Center(
                child: Text('$rank', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade400)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(subtitle!, style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(trailing, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade300),
          ],
        ),
      ),
    );
  }
}

// ── Donut chart ────────────────────────────────────────────────────────────────

class _DonutChart extends StatelessWidget {
  const _DonutChart({required this.entries, this.height = 220});
  final List<MapEntry<String, double>> entries;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = entries.fold(0.0, (s, e) => s + e.value.abs());
    if (total == 0) return const _EmptyChart(message: 'No data yet.');

    final colors = entries.map((e) => _sportColors[e.key] ?? _defaultSportColor).toList();

    return Column(
      children: [
        SizedBox(
          height: height * 0.6,
          child: CustomPaint(
            painter: _DonutPainter(entries: entries, colors: colors, total: total),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12, runSpacing: 6,
          children: [
            for (int i = 0; i < entries.length; i++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[i], borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 5),
                Text(entries[i].key, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ]),
          ],
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.entries, required this.colors, required this.total});
  final List<MapEntry<String, double>> entries;
  final List<Color> colors;
  final double total;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = min(cx, cy) - 4;
    final innerRadius = radius * 0.65;
    double startAngle = -pi / 2;
    for (int i = 0; i < entries.length; i++) {
      final sweep = (entries[i].value.abs() / total) * 2 * pi;
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius - innerRadius;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: (radius + innerRadius) / 2),
        startAngle, sweep - 0.02, false, paint,
      );
      startAngle += sweep;
    }

  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.entries != entries || old.total != total;
}

// ── Line chart ─────────────────────────────────────────────────────────────────

class _LineChart extends StatelessWidget {
  const _LineChart({required this.points, required this.stat, this.height = 200});
  final List<({String label, double value})> points;
  final String stat;
  final double height;

  @override
  Widget build(BuildContext context) {
    final prefix = stat == 'cards' ? '' : '\$';
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _LinePainter(points: points, lineColor: _burgundy, prefix: prefix),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter({required this.points, required this.lineColor, required this.prefix});
  final List<({String label, double value})> points;
  final Color lineColor;
  final String prefix;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    const labelHeight = 24.0;
    const leftPad = 40.0;
    final chartH = size.height - labelHeight;
    final chartW = size.width - leftPad;

    final values = points.map((p) => p.value).toList();
    final minVal = values.reduce(min);
    final maxVal = values.reduce(max);
    final range = (maxVal - minVal).abs();
    final effectiveMin = range == 0 ? minVal - 1 : minVal;
    final effectiveRange = range == 0 ? 2.0 : range * 1.1;

    double toX(int i) => leftPad + (i / (points.length - 1)) * chartW;
    double toY(double v) => chartH - ((v - effectiveMin) / effectiveRange) * chartH * 0.85 - chartH * 0.05;

    final path = Path();
    final fillPath = Path();
    for (int i = 0; i < points.length; i++) {
      final x = toX(i);
      final y = toY(points[i].value);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, chartH);
        fillPath.lineTo(x, y);
      } else {
        final px = toX(i - 1);
        final py = toY(points[i - 1].value);
        final cpx = (px + x) / 2;
        path.cubicTo(cpx, py, cpx, y, x, y);
        fillPath.cubicTo(cpx, py, cpx, y, x, y);
      }
    }
    fillPath.lineTo(toX(points.length - 1), chartH);
    fillPath.close();

    canvas.drawPath(fillPath, Paint()..color = lineColor.withValues(alpha: 0.08));
    canvas.drawPath(path, Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);

    // Dots (only when few points)
    if (points.length <= 20) {
      for (int i = 0; i < points.length; i++) {
        canvas.drawCircle(
          Offset(toX(i), toY(points[i].value)),
          3,
          Paint()..color = lineColor,
        );
      }
    }

    // X-axis labels (max 8)
    final step = max(1, (points.length / 8).ceil());
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < points.length; i += step) {
      tp.text = TextSpan(
        text: points[i].label,
        style: const TextStyle(fontSize: 9, color: Color(0xFF9CA3AF)),
      );
      tp.layout();
      tp.paint(canvas, Offset(toX(i) - tp.width / 2, chartH + 4));
    }

    // Y-axis labels (3 ticks)
    for (int t = 0; t <= 2; t++) {
      final v = effectiveMin + (effectiveRange * 0.85 * t / 2);
      final label = prefix + (v >= 1000
          ? '${(v / 1000).toStringAsFixed(0)}k'
          : v.toStringAsFixed(0));
      tp.text = TextSpan(text: label, style: const TextStyle(fontSize: 9, color: Color(0xFF9CA3AF)));
      tp.layout();
      final y = toY(v);
      tp.paint(canvas, Offset(0, y - tp.height / 2));

      canvas.drawLine(
        Offset(leftPad, y), Offset(size.width, y),
        Paint()..color = const Color(0xFFE5E7EB)..strokeWidth = 0.5,
      );
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.points != points;
}
