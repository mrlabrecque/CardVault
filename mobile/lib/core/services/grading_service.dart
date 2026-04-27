import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';

int _tryParseInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? 0;
  if (value is num) return value.toInt();
  return 0;
}

double _tryParseDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  if (value is num) return value.toDouble();
  return 0;
}

class GradingResult {
  const GradingResult({
    required this.psa9Avg,
    required this.psa10Avg,
    required this.psa9Count,
    required this.psa10Count,
  });

  final double psa9Avg;
  final double psa10Avg;
  final int psa9Count;
  final int psa10Count;

  factory GradingResult.fromJson(Map<String, dynamic> json) {
    final psa9  = json['psa9']  as Map<String, dynamic>? ?? {};
    final psa10 = json['psa10'] as Map<String, dynamic>? ?? {};
    return GradingResult(
      psa9Avg:   _tryParseDouble(psa9['avg']),
      psa10Avg:  _tryParseDouble(psa10['avg']),
      psa9Count: _tryParseInt(psa9['count']),
      psa10Count: _tryParseInt(psa10['count']),
    );
  }
}

class GradingService {
  GradingService(this._supabase);
  final SupabaseClient _supabase;

  Future<GradingResult> analyzeCard(String userCardId) async {
    final res = await _supabase.functions.invoke(
      'grading-analyze',
      body: {'userCardId': userCardId},
    );
    if (res.status != 200) {
      final detail = (res.data as Map<String, dynamic>?)?['error'] ?? 'Unknown error';
      throw Exception('Grading analysis failed: $detail');
    }
    return GradingResult.fromJson(res.data as Map<String, dynamic>);
  }
}

final gradingServiceProvider = Provider<GradingService>((ref) {
  return GradingService(ref.watch(supabaseProvider));
});
