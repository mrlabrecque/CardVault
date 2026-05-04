import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/fonts.dart';
import '../collection/widgets/card_detail_view.dart';
import '../collection/widgets/card_comps_section.dart';
import 'scan_screen.dart';

class ScanResultScreen extends ConsumerStatefulWidget {
  const ScanResultScreen({
    super.key,
    required this.detection,
    required this.sport,
  });

  final CardSightDetection detection;
  final String sport;

  @override
  ConsumerState<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends ConsumerState<ScanResultScreen> {
  late String _selectedParallelName;
  String? _masterCardId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedParallelName = widget.detection.card.parallel?.name ?? 'Base';
    _lookupMasterCard();
  }

  Future<void> _lookupMasterCard() async {
    try {
      final card = widget.detection.card;

      // Only proceed if we have an exact card match with an ID
      if (card.id == null) {
        setState(() => _loading = false);
        return;
      }

      // Look up our master card by cardsight_card_id
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('master_card_definitions')
          .select('id')
          .eq('cardsight_card_id', card.id!)
          .single();

      setState(() {
        _masterCardId = response['id'];
        _loading = false;
      });
    } catch (e) {
      // Card not in our DB yet — that's okay, just show the result without comps
      setState(() => _loading = false);
    }
  }

  void _goBackToScan() {
    context.pop();
  }

  void _addToCollection() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add to collection feature coming soon')),
    );
  }

  void _addToWishlist() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add to wishlist feature coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.detection.card;
    final colors = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: _goBackToScan,
          ),
          title: Align(
            alignment: Alignment.centerLeft,
            child: Text('Card Details', style: AppFonts.appBarTitle),
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: _goBackToScan,
        ),
        title: const Text('Card Details'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card detail view
            CardDetailView(
              setName: card.setName,
              releaseName: card.releaseName,
              parallelName: _selectedParallelName,
              year: card.year != null ? int.tryParse(card.year!) : null,
              sport: widget.sport,
              sections: const [CardDetailSection.hero],
              onAddToCollection: _addToCollection,
              onAddToWishlist: _addToWishlist,
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),

            // Grading info if detected
            if (widget.detection.grading != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_user, size: 16, color: Color(0xFF2563EB)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Graded — ${widget.detection.grading!.company.name}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1D4ED8),
                              ),
                            ),
                            Text(
                              'Confidence: ${widget.detection.grading!.confidence}',
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onSurface.withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Comps section (only if we have the master card ID)
            if (_masterCardId != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Recent Sales',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              CardCompsSection(
                masterCardId: _masterCardId!,
                parallelName: _selectedParallelName,
              ),
            ] else if (card.id != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFDBB726)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info, size: 16, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Sales data will appear after you add this card to your collection.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Action buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _addToCollection,
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF800020)),
                    child: const Text('Add to Collection'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _addToWishlist,
                    child: const Text('Add to Wishlist'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
