import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/cards_service.dart';
import '../../core/widgets/card_fan_loader.dart';

final _pendingParallelsProvider = FutureProvider<List<PendingParallel>>((ref) {
  return ref.watch(cardsServiceProvider).getPendingParallels();
});

class PendingParallelsScreen extends ConsumerStatefulWidget {
  const PendingParallelsScreen({super.key});

  @override
  ConsumerState<PendingParallelsScreen> createState() => _PendingParallelsScreenState();
}

class _PendingParallelsScreenState extends ConsumerState<PendingParallelsScreen> {
  String? _expandedId;
  final Map<String, TextEditingController> _serialCtrls = {};
  final Map<String, bool> _isAutoMap = {};
  final Map<String, TextEditingController> _hexCtrls = {};
  final Map<String, bool> _actingMap = {};

  @override
  void dispose() {
    for (final c in _serialCtrls.values) { c.dispose(); }
    for (final c in _hexCtrls.values) { c.dispose(); }
    super.dispose();
  }

  void _toggle(String id) {
    setState(() => _expandedId = _expandedId == id ? null : id);
    if (!_serialCtrls.containsKey(id)) {
      _serialCtrls[id] = TextEditingController();
      _hexCtrls[id] = TextEditingController();
      _isAutoMap[id] = false;
    }
  }

  Future<void> _promote(PendingParallel p) async {
    setState(() => _actingMap[p.id] = true);
    try {
      await ref.read(cardsServiceProvider).promotePendingParallel(
        id: p.id,
        setId: p.setId,
        name: p.name,
        serialMax: int.tryParse(_serialCtrls[p.id]?.text.trim() ?? ''),
        isAuto: _isAutoMap[p.id] ?? false,
        colorHex: _hexCtrls[p.id]?.text.trim(),
      );
      ref.invalidate(_pendingParallelsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _actingMap[p.id] = false);
    }
  }

  Future<void> _dismiss(String id) async {
    setState(() => _actingMap[id] = true);
    try {
      await ref.read(cardsServiceProvider).dismissPendingParallel(id);
      ref.invalidate(_pendingParallelsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _actingMap[id] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_pendingParallelsProvider);
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: async.when(
              loading: () => const Center(child: CardFanLoader()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (list) => list.isEmpty
                  ? Center(
                      child: Text('No pending parallels.',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4))),
                    )
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) => _PendingRow(
                        item: list[i],
                        expanded: _expandedId == list[i].id,
                        acting: _actingMap[list[i].id] ?? false,
                        serialCtrl: _serialCtrls[list[i].id],
                        hexCtrl: _hexCtrls[list[i].id],
                        isAuto: _isAutoMap[list[i].id] ?? false,
                        onTap: () => _toggle(list[i].id),
                        onIsAutoChanged: (v) => setState(() => _isAutoMap[list[i].id] = v),
                        onPromote: () => _promote(list[i]),
                        onDismiss: () => _dismiss(list[i].id),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({
    required this.item,
    required this.expanded,
    required this.acting,
    required this.serialCtrl,
    required this.hexCtrl,
    required this.isAuto,
    required this.onTap,
    required this.onIsAutoChanged,
    required this.onPromote,
    required this.onDismiss,
  });

  final PendingParallel item;
  final bool expanded;
  final bool acting;
  final TextEditingController? serialCtrl;
  final TextEditingController? hexCtrl;
  final bool isAuto;
  final VoidCallback onTap;
  final void Function(bool) onIsAutoChanged;
  final VoidCallback onPromote;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          onTap: onTap,
          title: Text(item.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          subtitle: Text(
            [if (item.releaseName != null) item.releaseName!, if (item.setName != null) item.setName!].join(' · '),
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.submissionCount > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade600,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('×${item.submissionCount}',
                      style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              const SizedBox(width: 4),
              Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: const Color(0xFF9CA3AF)),
            ],
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: serialCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Serial Max (optional)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: hexCtrl,
                      decoration: InputDecoration(
                        labelText: 'Color Hex (optional)',
                        hintText: '#C0C0C0',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: isAuto,
                  onChanged: onIsAutoChanged,
                  title: const Text('Auto', style: TextStyle(fontSize: 14)),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: acting ? null : onDismiss,
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade400),
                      child: const Text('Dismiss'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: acting ? null : onPromote,
                      child: acting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Promote'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
      ],
    );
  }
}
