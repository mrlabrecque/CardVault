import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/cards_service.dart';
import '../../core/widgets/app_breadcrumb.dart';

class AdminParallelsScreen extends ConsumerStatefulWidget {
  const AdminParallelsScreen({super.key, required this.release, required this.set});
  final ReleaseRecord release;
  final SetRecord set;

  @override
  ConsumerState<AdminParallelsScreen> createState() => _AdminParallelsScreenState();
}

class _AdminParallelsScreenState extends ConsumerState<AdminParallelsScreen> {
  List<SetParallel> _parallels = [];
  bool _loading = false;
  bool _saving = false;
  String? _deletingId;

  final _inputCtrl = TextEditingController();
  List<Map<String, dynamic>> _preview = [];
  bool _showPreview = false;

  @override
  void initState() {
    super.initState();
    _loadParallels();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadParallels() async {
    setState(() => _loading = true);
    try {
      final list = await ref.read(cardsServiceProvider).getParallels(widget.set.id);
      setState(() => _parallels = list);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteParallel(String id) async {
    setState(() => _deletingId = id);
    try {
      await ref.read(cardsServiceProvider).deleteParallel(id);
      setState(() => _parallels = _parallels.where((p) => p.id != id).toList());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  List<Map<String, dynamic>> _parse(String text) {
    return text.trim().split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) {
          final parts = l.split(':');
          return <String, dynamic>{
            'name':       parts[0].trim(),
            'serial_max': parts.length > 1 ? int.tryParse(parts[1].trim()) : null,
            'is_auto':    parts.length > 2 && parts[2].trim().toLowerCase() == 'auto',
          };
        }).toList();
  }

  void _buildPreview() {
    setState(() {
      _preview = _parse(_inputCtrl.text);
      _showPreview = _preview.isNotEmpty;
    });
  }

  Future<void> _importParallels() async {
    if (_preview.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(cardsServiceProvider).upsertParallels(widget.set.id, _preview);
      _inputCtrl.clear();
      setState(() { _preview = []; _showPreview = false; });
      await _loadParallels();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Parallels saved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          AppBreadcrumb(
            grandparent: 'Releases',
            onGrandparentBack: () => context.go('/admin/releases'),
            parent: widget.release.displayName,
            current: widget.set.name,
            onBack: () => context.pop(),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                // Existing parallels
                if (_parallels.isNotEmpty) ...[
                  _sectionLabel('Existing Parallels', colors),
                  const SizedBox(height: 8),
                  ..._parallels.map((p) => _ParallelRow(
                    parallel: p,
                    deleting: _deletingId == p.id,
                    onDelete: () => _deleteParallel(p.id),
                  )),
                  const SizedBox(height: 24),
                ],
                // Bulk importer
                _sectionLabel('Bulk Add Parallels', colors),
                const SizedBox(height: 4),
                Text(
                  'One per line: Name · Name:Max · Name:Max:auto',
                  style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.45)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _inputCtrl,
                  maxLines: 8,
                  onChanged: (_) => setState(() => _showPreview = false),
                  decoration: InputDecoration(
                    hintText: 'Silver\nGold:10\nPlatinum:5:auto',
                    hintStyle: TextStyle(fontSize: 13, color: colors.onSurface.withValues(alpha: 0.3)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _buildPreview,
                      child: const Text('Preview'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: (_showPreview && !_saving) ? _importParallels : null,
                      child: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Import'),
                    ),
                  ),
                ]),
                if (_showPreview && _preview.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionLabel('Preview (${_preview.length})', colors),
                  const SizedBox(height: 8),
                  ..._preview.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      const Icon(Icons.circle, size: 6, color: Color(0xFF9CA3AF)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(p['name'] as String, style: const TextStyle(fontSize: 13))),
                      if (p['serial_max'] != null)
                        Text('/${p['serial_max']}', style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                      if (p['is_auto'] == true) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(4)),
                          child: const Text('AUTO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ]),
                  )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, ColorScheme colors) => Text(
    text,
    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
        color: colors.onSurface.withValues(alpha: 0.5), letterSpacing: 0.3),
  );
}

class _ParallelRow extends StatelessWidget {
  const _ParallelRow({required this.parallel, required this.deleting, required this.onDelete});
  final SetParallel parallel;
  final bool deleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(parallel.name, style: const TextStyle(fontSize: 14)),
          ),
          if (parallel.serialMax != null)
            Text('/${parallel.serialMax}', style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
          if (parallel.isAuto) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(4)),
              child: const Text('AUTO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          ],
          const SizedBox(width: 8),
          deleting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300),
                  onPressed: onDelete,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
        ],
      ),
    );
  }
}
