import 'package:flutter/material.dart';
import '../../core/utils/adaptive_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/market_movers_service.dart';
import '../../core/models/market_mover.dart';

const _burgundy = Color(0xFF800020);

class MarketMoversScreen extends ConsumerStatefulWidget {
  const MarketMoversScreen({super.key});

  @override
  ConsumerState<MarketMoversScreen> createState() => _MarketMoversScreenState();
}

class _MarketMoversScreenState extends ConsumerState<MarketMoversScreen> {
  String? _selectedSport;
  int _selectedDays = 7;

  @override
  Widget build(BuildContext context) {
    final moversAsync = ref.watch(marketMoversProvider(_selectedSport));

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: moversAsync.when(
        loading: () => _buildSkeleton(),
        error: (e, _) => _buildError(e.toString()),
        data: (data) => _buildContent(data),
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        const SizedBox(height: 16),
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 24),
        ...List.generate(5, (_) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: 72,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        )),
      ],
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Color(0xFF9CA3AF)),
          const SizedBox(height: 16),
          Text('Error: $error', style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  void _showMarketMoversInfo(BuildContext context) {
    showAdaptiveSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.info_outline, size: 18, color: Color(0xFFF97316)),
                ),
                const SizedBox(width: 12),
                const Text(
                  'What is Market Movers',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Market Movers shows players whose card values are rapidly changing based on recent eBay sold listings.',
              style: TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5),
            ),
            const SizedBox(height: 10),
            const Text(
              '🔥 Rising — Cards with the biggest price increases\n🧊 Cooling — Cards with the biggest price decreases',
              style: TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.5),
            ),
            const SizedBox(height: 10),
            const Text(
              'The percentage shows the price change. The volume indicator shows whether sales activity is increasing or decreasing.',
              style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(MarketMoversData data) {
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(marketMoversProvider(_selectedSport)),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          // ── Breadcrumb ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.go('/tools'),
                  child: const Text('Tools', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF9CA3AF))),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.chevron_right, size: 14, color: Color(0xFFD1D5DB)),
                ),
                const Text('Market Movers', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showMarketMoversInfo(context),
                  child: const Icon(Icons.info_outline, size: 16, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ),

          // ── Sport filters (scrollable) ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: const Text('All'),
                    selected: _selectedSport == null,
                    onSelected: (_) => setState(() => _selectedSport = null),
                  ),
                ),
                ...['NBA', 'NFL', 'MLB', 'NHL'].map((sport) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(sport),
                    selected: _selectedSport == sport,
                    onSelected: (_) => setState(() => _selectedSport = sport),
                  ),
                )),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── No data state ────────────────────────────────────────────────────
          if (data.hot.isEmpty && data.cold.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    const Text('📊', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    const Text('No data yet', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 4),
                    const Text('Check back after Sunday — data refreshes weekly.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)), textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          else ...[

            // ── Rising section + Period toggle ──────────────────────────────────
            if (data.hot.isNotEmpty) ...[
              Row(
                children: [
                  const Text('🔥 Rising', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text('${data.hot.length} players', style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                  const Spacer(),
                  _PeriodToggle(
                    selected: _selectedDays,
                    onSelect: (days) => setState(() => _selectedDays = days),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ..._buildMoverRows(data.hot, isHot: true),
              const SizedBox(height: 24),
            ],

            // ── Cooling section + Period toggle ──────────────────────────────────
            if (data.cold.isNotEmpty) ...[
              Row(
                children: [
                  const Text('🧊 Cooling', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Text('${data.cold.length} players', style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                  const Spacer(),
                  _PeriodToggle(
                    selected: _selectedDays,
                    onSelect: (days) => setState(() => _selectedDays = days),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ..._buildMoverRows(data.cold, isHot: false),
            ],
          ],
        ],
      ),
    );
  }

  List<Widget> _buildMoverRows(List<MarketMover> movers, {required bool isHot}) {
    return movers.map((mover) {
      final changeColor = mover.isTrendingUp ? const Color(0xFF059669) : const Color(0xFFef4444);
      final changeBgColor = mover.isTrendingUp ? const Color(0xFFecfdf5) : const Color(0xFFFEF2F2);
      final volumeColor = mover.volumeChangePct > 0 ? '↑' : '↓';

      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mover.playerName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(mover.sport, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFf3f4f6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '\$${mover.currentAvg.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF374151)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: changeBgColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${mover.priceChangePct > 0 ? '+' : ''}${mover.priceChangePct.toStringAsFixed(1)}%',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: changeColor),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$volumeColor ${(mover.volumeChangePct.abs()).toStringAsFixed(0)}% vol',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ],
        ),
      );
    }).toList();
  }
}

class _PeriodToggle extends StatelessWidget {
  final int selected;
  final Function(int) onSelect;

  const _PeriodToggle({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [7, 30].map((days) {
          final active = selected == days;
          return GestureDetector(
            onTap: () => onSelect(days),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              color: active ? _burgundy : Colors.transparent,
              child: Text(
                '${days}d',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: active ? Colors.white : const Color(0xFF6B7280),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

