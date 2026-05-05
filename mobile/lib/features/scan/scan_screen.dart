import 'dart:convert';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/fonts.dart';
import '../../core/widgets/app_bar_avatar.dart';
import '../../core/widgets/app_overflow_menu.dart';

// CardSight detection result model
class CardSightDetection {
  final String confidence; // High, Medium, Low
  final CardSightCard card;
  final GradingInfo? grading;

  CardSightDetection({
    required this.confidence,
    required this.card,
    this.grading,
  });

  factory CardSightDetection.fromJson(Map<String, dynamic> json) {
    return CardSightDetection(
      confidence: json['confidence'] ?? 'Low',
      card: CardSightCard.fromJson(json['card'] ?? {}),
      grading: json['grading'] != null ? GradingInfo.fromJson(json['grading']) : null,
    );
  }
}

class CardSightCard {
  final String? id; // exact match only
  final String? name; // player name (exact match only)
  final String? number; // card number (exact match only)
  final String? year;
  final String? manufacturer;
  final String? releaseName;
  final String? setName;
  final String? releaseId;
  final String? setId;
  final String? segmentId;
  final ParallelInfo? parallel;

  CardSightCard({
    this.id,
    this.name,
    this.number,
    this.year,
    this.manufacturer,
    this.releaseName,
    this.setName,
    this.releaseId,
    this.setId,
    this.segmentId,
    this.parallel,
  });

  factory CardSightCard.fromJson(Map<String, dynamic> json) {
    return CardSightCard(
      id: json['id'],
      name: json['name'],
      number: json['number'],
      year: json['year'],
      manufacturer: json['manufacturer'],
      releaseName: json['releaseName'],
      setName: json['setName'],
      releaseId: json['releaseId'],
      setId: json['setId'],
      segmentId: json['segmentId'],
      parallel: json['parallel'] != null ? ParallelInfo.fromJson(json['parallel']) : null,
    );
  }
}

class ParallelInfo {
  final String id;
  final String name;
  final int? numberedTo;

  ParallelInfo({required this.id, required this.name, this.numberedTo});

  factory ParallelInfo.fromJson(Map<String, dynamic> json) {
    return ParallelInfo(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Base',
      numberedTo: json['numberedTo'],
    );
  }
}

class GradingInfo {
  final String confidence;
  final GradingCompany company;

  GradingInfo({required this.confidence, required this.company});

  factory GradingInfo.fromJson(Map<String, dynamic> json) {
    return GradingInfo(
      confidence: json['confidence'] ?? 'Low',
      company: GradingCompany.fromJson(json['company'] ?? {}),
    );
  }
}

class GradingCompany {
  final String? id;
  final String name;

  GradingCompany({this.id, required this.name});

  factory GradingCompany.fromJson(Map<String, dynamic> json) {
    return GradingCompany(
      id: json['id'],
      name: json['name'] ?? 'Unknown',
    );
  }
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

enum _ScanState { sportPicker, processing, result, error }

class _ScanScreenState extends State<ScanScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final _supabase = Supabase.instance.client;

  _ScanState _state = _ScanState.sportPicker;
  String _selectedSport = '';
  CardSightDetection? _detection;
  String? _errorMessage;

  static const _sports = [
    ('Baseball', 'baseball', '⚾', Color(0xFFB45309)),
    ('Basketball', 'basketball', '🏀', Color(0xFFF97316)),
    ('Football', 'football', '🏈', Color(0xFF8B5CF6)),
    ('Hockey', 'hockey', '🏒', Color(0xFF2563EB)),
  ];

  Future<void> _selectSport(String sport) async {
    setState(() => _selectedSport = sport);
    // Auto-launch camera after brief delay to allow state update
    await Future.delayed(const Duration(milliseconds: 100));
    if (mounted) _capturePhoto();
  }

  Future<void> _capturePhoto() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );

    if (file == null) {
      // User cancelled — go back to sport picker
      if (mounted) {
        setState(() {
          _state = _ScanState.sportPicker;
          _selectedSport = '';
        });
      }
      return;
    }

    if (mounted) setState(() => _state = _ScanState.processing);

    try {
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);

      final res = await _supabase.functions.invoke(
        'identify-card',
        body: {'imageBase64': base64String, 'sport': _selectedSport},
      );

      if (res.status != 200) {
        throw Exception('Identification failed: ${res.status}');
      }

      final data = res.data as Map<String, dynamic>;

      if (data['error'] != null) {
        throw Exception(data['error']);
      }

      final detections = data['detections'] as List<dynamic>? ?? [];

      if (detections.isEmpty) {
        if (mounted) {
          setState(() {
            _state = _ScanState.error;
            _errorMessage = 'No cards detected. Try again with a clearer photo.';
          });
        }
        return;
      }

      final detection = CardSightDetection.fromJson(detections[0]);

      if (mounted) {
        setState(() {
          _state = _ScanState.result;
          _detection = detection;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _ScanState.error;
          _errorMessage = 'Error: ${e.toString()}';
        });
      }
    }
  }

  void _resetToSportPicker() {
    setState(() {
      _state = _ScanState.sportPicker;
      _selectedSport = '';
      _detection = null;
      _errorMessage = null;
    });
  }

  void _goToCardDetails() {
    if (_detection == null) return;
    context.push('/scan/result', extra: {'detection': _detection, 'sport': _selectedSport});
  }

  Color _getConfidenceColor(String confidence) {
    switch (confidence.toLowerCase()) {
      case 'high':
        return const Color(0xFF10B981); // green
      case 'medium':
        return const Color(0xFFF59E0B); // amber
      case 'low':
      default:
        return const Color(0xFFEF4444); // red
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _state == _ScanState.sportPicker ? _buildSportPicker() : _buildContent(),
    );
  }

  Widget _buildSportPicker() {
    return Scaffold(
      appBar: AppBar(
        title: Align(
          alignment: Alignment.centerLeft,
          child: Text('Scan Card', style: AppFonts.appBarTitle),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: const [
          AppOverflowMenu(),
          AppBarAvatar(iconOnly: true),
        ],
      ),
      body: Column(
        children: [
          Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              children: [
                GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.2,
                  children: _sports.map((sport) {
                    final (name, value, emoji, tintColor) = sport;
                    return GestureDetector(
                      onTap: () => _selectSport(value),
                      child: Container(
                        decoration: BoxDecoration(
                          color: tintColor.withValues(alpha: 0.15),
                          border: Border.all(
                            color: tintColor.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(emoji, style: const TextStyle(fontSize: 48)),
                            const SizedBox(height: 12),
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ],
      ),
    );
  }

  Widget _buildContent() {
    if (_state == _ScanState.processing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFF800020)),
            const SizedBox(height: 20),
            Text(
              'Identifying card…',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
    }

    if (_state == _ScanState.error) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _errorMessage ?? 'An error occurred',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            const SizedBox(height: 24),
            AdaptiveButton.child(
              onPressed: _resetToSportPicker,
              style: AdaptiveButtonStyle.filled,
              color: const Color(0xFF800020),
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    // Result state
    final detection = _detection!;
    final card = detection.card;
    final color = _getConfidenceColor(detection.confidence);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: const [
          AppOverflowMenu(),
          AppBarAvatar(iconOnly: true),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Confidence pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    border: Border.all(color: color),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    detection.confidence,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Player name or "Partial Match"
                if (card.name != null)
                  Text(
                    card.name!,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  Text(
                    'Partial Match',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                const SizedBox(height: 12),

                // Info chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (card.year != null) _buildChip(card.year!),
                    if (card.manufacturer != null) _buildChip(card.manufacturer!),
                    if (card.releaseName != null) _buildChip(card.releaseName!),
                    if (card.setName != null) _buildChip(card.setName!),
                  ],
                ),

                const SizedBox(height: 16),

                // Parallel chip
                if (card.parallel != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF800020).withValues(alpha: 0.3),
                      border: Border.all(color: const Color(0xFF800020)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      card.parallel!.numberedTo != null
                          ? '${card.parallel!.name} /${card.parallel!.numberedTo}'
                          : card.parallel!.name,
                      style: const TextStyle(
                        color: Color(0xFF800020),
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],

                // Grading badge
                if (detection.grading != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      border: Border.all(color: Colors.blue),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '🔒 ${detection.grading!.company.name}',
                      style: const TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // View Card Details button
                AdaptiveButton.child(
                  onPressed: _goToCardDetails,
                  style: AdaptiveButtonStyle.filled,
                  color: const Color(0xFF800020),
                  child: const Text('View Card Details'),
                ),

                const SizedBox(height: 12),

                // Try Again button
                AdaptiveButton.child(
                  onPressed: _resetToSportPicker,
                  style: AdaptiveButtonStyle.bordered,
                  child: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      );
  }

  Widget _buildChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.black54, fontSize: 12),
      ),
    );
  }
}
