import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/auth_service.dart';

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
      psa9Avg:   (psa9['avg']   as num?)?.toDouble() ?? 0,
      psa10Avg:  (psa10['avg']  as num?)?.toDouble() ?? 0,
      psa9Count: (psa9['count'] as num?)?.toInt()    ?? 0,
      psa10Count:(psa10['count']as num?)?.toInt()    ?? 0,
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
