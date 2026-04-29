import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/cards_service.dart';

int? _tryParseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  if (value is num) return value.toInt();
  return null;
}

const _years = ['2026','2025','2024','2023','2022','2021','2020','2019','2018','2017'];

const _sports = [
  ('Baseball',   'baseball'),
  ('Basketball', 'basketball'),
  ('Football',   'football'),
  ('Soccer',     'soccer'),
  ('Hockey',     'hockey'),
];

class CatalogImportScreen extends ConsumerStatefulWidget {
  const CatalogImportScreen({super.key});

  @override
  ConsumerState<CatalogImportScreen> createState() => _CatalogImportScreenState();
}

class _CatalogImportScreenState extends ConsumerState<CatalogImportScreen> {
  String _year = DateTime.now().year.toString();
  String _segment = 'baseball';
  bool _importing = false;
  int _skip = 0;
  Map<String, dynamic>? _lastResult;

  Future<void> _import() async {
    setState(() { _importing = true; _lastResult = null; });
    try {
      final result = await ref.read(cardsServiceProvider).bulkImportReleases(
        year: int.parse(_year),
        segment: _segment,
        skip: _skip,
      );
      setState(() {
        _lastResult = result;
        if ((_tryParseInt(result['imported']) ?? 0) > 0) _skip += 100;
      });
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
    final imported = _tryParseInt(_lastResult?['imported']);
    final total    = _tryParseInt(_lastResult?['total']);

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                // Filters
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _year,
                      decoration: _inputDec('Year'),
                      items: _years.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
                      onChanged: (v) => setState(() { _year = v!; _skip = 0; _lastResult = null; }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _segment,
                      decoration: _inputDec('Sport'),
                      items: _sports.map((s) => DropdownMenuItem(value: s.$2, child: Text(s.$1))).toList(),
                      onChanged: (v) => setState(() { _segment = v!; _skip = 0; _lastResult = null; }),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _importing ? null : _import,
                  child: _importing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_skip == 0 ? 'Import 100 Releases' : 'Load Next 100 (skip $_skip)'),
                ),
                if (_lastResult != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Result', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.onSurface.withValues(alpha: 0.5))),
                        const SizedBox(height: 8),
                        Text('$imported imported  ·  $total from CardSight',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        if ((total ?? 0) == 100) ...[
                          const SizedBox(height: 4),
                          Text('Full page returned — use "Load Next 100" for more.',
                              style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.5))),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDec(String label) => InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    isDense: true,
  );
}
