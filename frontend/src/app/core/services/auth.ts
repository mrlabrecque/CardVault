import { Injectable, signal, computed } from '@angular/core';
import { Router } from '@angular/router';
import { createClient, SupabaseClient, User, Session } from '@supabase/supabase-js';
import { environment } from '../../../environments/environment';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private supabase: SupabaseClient;

  private _user = signal<User | null>(null);
  private _session = signal<Session | null>(null);
  private _isAppAdmin = signal(false);

  readonly user = this._user.asReadonly();
  readonly isAuthenticated = computed(() => this._user() !== null);
  readonly isAppAdmin = this._isAppAdmin.asReadonly();

  constructor(private router: Router) {
    this.supabase = createClient(environment.supabaseUrl, environment.supabaseAnonKey);

    // Restore existing session on app load
    this.supabase.auth.getSession().then(({ data }) => {
      this._session.set(data.session);
      this._user.set(data.session?.user ?? null);
      if (data.session?.user) this.fetchProfile(data.session.user.id);
    });

    // React to all future auth state changes (login, logout, token refresh)
    this.supabase.auth.onAuthStateChange((event, session) => {
      this._session.set(session);
      this._user.set(session?.user ?? null);

      if (event === 'PASSWORD_RECOVERY') {
        // Reset link clicked — redirect to set-password page instead of dashboard
        this.router.navigate(['/set-password']);
      } else if (event === 'SIGNED_IN' && session?.user) {
        this.fetchProfile(session.user.id);
        this.router.navigate(['/dashboard']);
      } else if (event === 'SIGNED_OUT') {
        this._isAppAdmin.set(false);
        this.router.navigate(['/login']);
      }
    });
  }

  private async fetchProfile(userId: string) {
    // Ensure a row exists for users created before the DB trigger was added.
    // ignoreDuplicates: true means existing rows (and their is_app_admin) are untouched.
    const email = this._user()?.email ?? null;

    // Create the row if it doesn't exist yet (ignoreDuplicates preserves is_app_admin on existing rows)
    await this.supabase
      .from('profiles')
      .upsert({ id: userId, email, is_app_admin: false }, { onConflict: 'id', ignoreDuplicates: true });

    // Always sync the email regardless (handles email changes, pre-existing rows)
    await this.supabase
      .from('profiles')
      .update({ email })
      .eq('id', userId);

    const { data } = await this.supabase
      .from('profiles')
      .select('is_app_admin')
      .eq('id', userId)
      .single();

    this._isAppAdmin.set(data?.is_app_admin ?? false);
  }

  async signInWithEmail(email: string) {
    return this.supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: `${window.location.origin}/dashboard` },
    });
  }

  async signInWithPassword(email: string, password: string) {
    return this.supabase.auth.signInWithPassword({ email, password });
  }

  async sendPasswordReset(email: string) {
    return this.supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/set-password`,
    });
  }

  async updatePassword(newPassword: string) {
    return this.supabase.auth.updateUser({ password: newPassword });
  }

  async signOut() {
    return this.supabase.auth.signOut();
  }

  /** Direct session check — used by AuthGuard to avoid timing issues on first load. */
  async getSession(): Promise<Session | null> {
    const { data } = await this.supabase.auth.getSession();
    return data.session;
  }

  getClient(): SupabaseClient {
    return this.supabase;
  }
}
