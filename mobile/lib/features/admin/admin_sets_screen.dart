import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/cards_service.dart';
import '../../core/widgets/app_breadcrumb.dart';
import '../../core/widgets/card_fan_loader.dart';

class AdminSetsScreen extends ConsumerStatefulWidget {
  const AdminSetsScreen({super.key, required this.release});
  final ReleaseRecord release;

  @override
  ConsumerState<AdminSetsScreen> createState() => _AdminSetsScreenState();
}

class _AdminSetsScreenState extends ConsumerState<AdminSetsScreen> {
  List<SetRecord> _sets = [];
  bool _loading = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _loadSets();
  }

  Future<void> _loadSets() async {
    setState(() => _loading = true);
    try {
      final sets = await ref.read(cardsServiceProvider).getSetsForRelease(widget.release.id);
      setState(() => _sets = sets);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _importFromCardSight() async {
    final csId = widget.release.cardsightId;
    if (csId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No CardSight ID for this release.')),
      );
      return;
    }
    setState(() => _importing = true);
    try {
      await ref.read(cardsServiceProvider).importSetsForRelease(
        cardsightReleaseId: csId,
        releaseName: widget.release.name,
        releaseYear: widget.release.year?.toString(),
      );
      await _loadSets();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(
        children: [
          AppBreadcrumb(
            parent: 'Releases',
            current: widget.release.displayName,
            onBack: () => context.pop(),
          ),
          if (_loading || _importing)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _loading && _sets.isEmpty
                ? const Center(child: CardFanLoader())
                : _sets.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('No sets in database.',
                                style: TextStyle(color: colors.onSurface.withValues(alpha: 0.4))),
                            const SizedBox(height: 16),
                            if (widget.release.cardsightId != null)
                              FilledButton.icon(
                                onPressed: _importing ? null : _importFromCardSight,
                                icon: const Icon(Icons.download_outlined, size: 16),
                                label: const Text('Import from CardSight'),
                              ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _sets.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final s = _sets[i];
                          return ListTile(
                            title: Text(s.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            subtitle: s.cardCount != null
                                ? Text('${s.cardCount} cards', style: const TextStyle(fontSize: 12))
                                : null,
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () => context.push(
                              '/admin/releases/${widget.release.id}/sets/${s.id}/parallels',
                              extra: (widget.release, s),
                            ),
                          );
                        },
                      ),
          ),
          if (_sets.isNotEmpty && widget.release.cardsightId != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: OutlinedButton.icon(
                onPressed: _importing ? null : _importFromCardSight,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Re-import sets from CardSight'),
              ),
            ),
        ],
      ),
    );
  }
}
