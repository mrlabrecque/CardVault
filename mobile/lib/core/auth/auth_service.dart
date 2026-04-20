import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseProvider).auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(supabaseProvider).auth.currentUser;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});

final isAppAdminProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return false;
  final supabase = ref.watch(supabaseProvider);
  final data = await supabase
      .from('profiles')
      .select('is_app_admin')
      .eq('id', user.id)
      .single();
  return data['is_app_admin'] as bool? ?? false;
});

class AuthService {
  AuthService(this._supabase);
  final SupabaseClient _supabase;

  Future<void> signInWithEmail(String email) async {
    await _supabase.auth.signInWithOtp(email: email);
  }

  Future<void> signInWithPassword(String email, String password) async {
    await _supabase.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(supabaseProvider));
});
