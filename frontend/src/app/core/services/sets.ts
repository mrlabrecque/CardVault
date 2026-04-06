import { Injectable } from '@angular/core';
import { AuthService } from './auth';

export interface ChecklistRecord {
  id: string;
  set_id: string;
  name: string;       // e.g. "Base Set", "Fireworks", "Monopoly Money"
  prefix: string | null; // e.g. "F-", "M-"; null = base set
  created_at: string;
}

export interface SetRecord {
  id: string;
  name: string;
  year: number;
  sport: string;
  release_type: string;
  ebay_search_template: string | null;
  set_slug: string;
  created_at: string;
}

export type CreateSetPayload = Omit<SetRecord, 'id' | 'created_at'>;

export interface SetParallel {
  id: string;
  checklist_id: string;
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
  set_id: string;
  name: string;
  submitted_by: string | null;
  submission_count: number;
  status: 'pending' | 'approved' | 'dismissed';
  created_at: string;
  // joined
  sets?: { name: string; year: number; sport: string };
}

@Injectable({ providedIn: 'root' })
export class SetsService {
  constructor(private auth: AuthService) {}

  private get db() {
    return this.auth.getClient().from('sets');
  }

  async getSets(): Promise<SetRecord[]> {
    const { data } = await this.db
      .select('*')
      .order('year', { ascending: false })
      .order('name');
    return (data as SetRecord[]) ?? [];
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

  async createSet(payload: CreateSetPayload) {
    return this.db.insert(payload).select().single();
  }

  async searchSets(query: string): Promise<SetRecord[]> {
    const { data } = await this.db
      .select('*')
      .ilike('name', `%${query}%`)
      .order('year', { ascending: false })
      .limit(10);
    return (data as SetRecord[]) ?? [];
  }

  // ── Checklists ────────────────────────────────────────────────────────────

  async getChecklists(setId: string): Promise<ChecklistRecord[]> {
    const { data } = await this.auth.getClient()
      .from('checklists')
      .select('*')
      .eq('set_id', setId)
      .order('name');
    return (data as ChecklistRecord[]) ?? [];
  }

  async createChecklist(setId: string, name: string, prefix: string | null) {
    return this.auth.getClient()
      .from('checklists')
      .insert({ set_id: setId, name, prefix })
      .select()
      .single();
  }

  async deleteChecklist(id: string) {
    return this.auth.getClient().from('checklists').delete().eq('id', id);
  }

  // ── Parallels ─────────────────────────────────────────────────────────────

  private get parallelsDb() {
    return this.auth.getClient().from('set_parallels');
  }

  async getParallels(checklistId: string): Promise<SetParallel[]> {
    const { data } = await this.parallelsDb
      .select('*')
      .eq('checklist_id', checklistId)
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
  async submitPendingParallel(setId: string, name: string): Promise<void> {
    const { data: { user } } = await this.auth.getClient().auth.getUser();
    await this.auth.getClient().rpc('submit_pending_parallel', {
      p_set_id: setId,
      p_name: name,
      p_user_id: user?.id ?? null,
    });
  }

  async getPendingParallels(): Promise<PendingParallel[]> {
    const { data } = await this.pendingDb
      .select('*, sets(name, year, sport)')
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
    // Parallels belong to checklists — default to the base checklist (null prefix) of the set
    const checklists = await this.getChecklists(pending.set_id);
    const baseChecklist = checklists.find(c => c.prefix === null) ?? checklists[0];
    if (!baseChecklist) return { error: { message: 'No checklist found for this set' } };

    const { error } = await this.parallelsDb.upsert(
      {
        checklist_id: baseChecklist.id,
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
