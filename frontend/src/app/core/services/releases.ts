import { Injectable } from '@angular/core';
import { AuthService } from './auth';

// A Release is the top-level product (e.g. "2025 Topps Chrome").
// A Set is a subset within a release (e.g. "Base", "Heavy Hitters", "Fresh Faces").
// Parallels are variations of a set (e.g. "Silver", "Sapphire", "X-Factor").

export interface ReleaseRecord {
  id: string;
  name: string;
  year: number;
  sport: string;
  release_type: string;
  ebay_search_template: string | null;
  set_slug: string;
  created_at: string;
}

export type CreateReleasePayload = Omit<ReleaseRecord, 'id' | 'created_at'>;

// A SetRecord represents a named subset within a release (what was previously called a "checklist").
// The DB column `set_id` is the FK to the parent releases table.
export interface SetRecord {
  id: string;
  set_id: string;       // FK → releases.id
  name: string;         // e.g. "Base Set", "Heavy Hitters", "Fresh Faces"
  prefix: string | null; // e.g. "F-", "M-"; null = base set
  created_at: string;
}

export interface SetParallel {
  id: string;
  checklist_id: string; // FK → sets.id (DB column kept as-is)
  name: string;
  serial_max: number | null;
  is_auto: boolean;
  color_hex: string | null;
  sort_order: number;
  created_at: string;
}

export type UpsertParallelPayload = Omit<SetParallel, 'id' | 'created_at'>;

export interface PendingParallel {
  id: string;
  set_id: string;       // FK → releases.id (DB column kept as-is)
  name: string;
  submitted_by: string | null;
  submission_count: number;
  status: 'pending' | 'approved' | 'dismissed';
  created_at: string;
  // joined
  releases?: { name: string; year: number; sport: string };
}

@Injectable({ providedIn: 'root' })
export class ReleasesService {
  constructor(private auth: AuthService) {}

  private get db() {
    return this.auth.getClient().from('releases');
  }

  // ── Releases ──────────────────────────────────────────────────────────────

  async getReleases(): Promise<ReleaseRecord[]> {
    const { data } = await this.db
      .select('*')
      .order('year', { ascending: false })
      .order('name');
    return (data as ReleaseRecord[]) ?? [];
  }

  async checkDuplicate(name: string, year: number, sport: string): Promise<boolean> {
    const { data } = await this.db
      .select('id')
      .ilike('name', name)
      .eq('year', year)
      .eq('sport', sport)
      .limit(1);
    return (data?.length ?? 0) > 0;
  }

  async createRelease(payload: CreateReleasePayload) {
    return this.db.insert(payload).select().single();
  }

  async searchReleases(query: string): Promise<ReleaseRecord[]> {
    const { data } = await this.db
      .select('*')
      .ilike('name', `%${query}%`)
      .order('year', { ascending: false })
      .limit(10);
    return (data as ReleaseRecord[]) ?? [];
  }

  // ── Sets (subsets within a release) ──────────────────────────────────────

  async getSets(releaseId: string): Promise<SetRecord[]> {
    const { data } = await this.auth.getClient()
      .from('sets')
      .select('*')
      .eq('set_id', releaseId)
      .order('name');
    return (data as SetRecord[]) ?? [];
  }

  async createSet(releaseId: string, name: string, prefix: string | null) {
    return this.auth.getClient()
      .from('sets')
      .insert({ set_id: releaseId, name, prefix })
      .select()
      .single();
  }

  async deleteSet(id: string) {
    return this.auth.getClient().from('sets').delete().eq('id', id);
  }

  // ── Parallels ─────────────────────────────────────────────────────────────

  private get parallelsDb() {
    return this.auth.getClient().from('set_parallels');
  }

  async getParallels(setId: string): Promise<SetParallel[]> {
    const { data } = await this.parallelsDb
      .select('*')
      .eq('checklist_id', setId)
      .order('sort_order')
      .order('name');
    return (data as SetParallel[]) ?? [];
  }

  async upsertParallels(parallels: UpsertParallelPayload[]) {
    return this.parallelsDb
      .upsert(parallels, { onConflict: 'checklist_id,name', ignoreDuplicates: false });
  }

  async deleteParallel(id: string) {
    return this.parallelsDb.delete().eq('id', id);
  }

  // ── Pending Parallels ─────────────────────────────────────────────────────

  private get pendingDb() {
    return this.auth.getClient().from('pending_parallels');
  }

  /** Called from the Add Card dialog when user picks "Other…". Fire-and-forget safe. */
  async submitPendingParallel(releaseId: string, name: string): Promise<void> {
    const { data: { user } } = await this.auth.getClient().auth.getUser();
    await this.auth.getClient().rpc('submit_pending_parallel', {
      p_set_id: releaseId,
      p_name: name,
      p_user_id: user?.id ?? null,
    });
  }

  async getPendingParallels(): Promise<PendingParallel[]> {
    const { data } = await this.pendingDb
      .select('*, releases(name, year, sport)')
      .eq('status', 'pending')
      .order('submission_count', { ascending: false })
      .order('created_at');
    return (data as PendingParallel[]) ?? [];
  }

  async getPendingCount(): Promise<number> {
    const { count } = await this.pendingDb
      .select('id', { count: 'exact', head: true })
      .eq('status', 'pending');
    return count ?? 0;
  }

  async approveParallel(
    pending: PendingParallel,
    extras: { serial_max: number | null; is_auto: boolean; color_hex: string | null }
  ) {
    // Parallels belong to sets — default to the base set (null prefix) of the release
    const sets = await this.getSets(pending.set_id);
    const baseSet = sets.find(s => s.prefix === null) ?? sets[0];
    if (!baseSet) return { error: { message: 'No set found for this release' } };

    const { error } = await this.parallelsDb.upsert(
      {
        checklist_id: baseSet.id,
        name: pending.name,
        serial_max: extras.serial_max,
        is_auto: extras.is_auto,
        color_hex: extras.color_hex,
        sort_order: 999,
      },
      { onConflict: 'checklist_id,name', ignoreDuplicates: false }
    );
    if (error) return { error };
    return this.pendingDb.update({ status: 'approved' }).eq('id', pending.id);
  }

  async dismissParallel(id: string) {
    return this.pendingDb.update({ status: 'dismissed' }).eq('id', id);
  }
}
