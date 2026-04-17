import { Injectable, inject, signal } from '@angular/core';
import { AuthService } from './auth';
import { environment } from '../../../environments/environment';

export type AlertStatus = 'active' | 'paused' | 'triggered';

export interface WishlistMatch {
  id: string;
  wishlist_id: string;
  ebay_item_id: string | null;
  title: string;
  price: number;
  listing_type: 'AUCTION' | 'FIXED_PRICE';
  url: string | null;
  image_url: string | null;
  found_at: string;
}

export interface WishlistItem {
  id: string;
  player: string | null;
  year: number | null;
  set_name: string | null;
  parallel: string | null;
  card_number: string | null;
  is_rookie: boolean;
  is_auto: boolean;
  is_patch: boolean;
  serial_max: number | null;
  grade: string | null;
  ebay_query: string | null;
  exclude_terms: string[];
  dismissed_ebay_ids: string[];
  target_price: number | null;
  alert_status: AlertStatus;
  last_seen_price: number | null;
  last_checked_at: string | null;
  created_at: string;
  matches: WishlistMatch[];
}

export interface WishlistFormData {
  player: string;
  year: number | null;
  set_name: string;
  parallel: string;
  card_number: string;
  is_rookie: boolean;
  is_auto: boolean;
  is_patch: boolean;
  serial_max: number | null;
  grade: string;
  ebay_query: string;
  exclude_terms: string[];
  target_price: number | null;
}

/**
 * Build an eBay search query from wishlist form fields.
 * Mirrors buildCardEbayQuery() in backend/src/services/comps.service.ts — keep in sync.
 */
export function buildEbayQuery(f: Pick<WishlistFormData, 'player' | 'year' | 'set_name' | 'parallel' | 'card_number' | 'grade' | 'serial_max' | 'is_rookie' | 'is_auto' | 'is_patch'>): string {
  const parts: string[] = [];
  if (f.year)        parts.push(String(f.year));
  if (f.set_name)    parts.push(f.set_name);
  if (f.player)      parts.push(f.player);
  if (f.card_number) parts.push(`#${f.card_number}`);

  // Strip trailing /N from parallel label (e.g. "Silver /99" → "Silver")
  const parallelLabel = (f.parallel ?? '').replace(/\s*\/\d+$/, '').trim();
  if (parallelLabel && parallelLabel.toLowerCase() !== 'base') parts.push(parallelLabel);

  if (f.is_auto)    parts.push('Auto');
  if (f.is_patch)   parts.push('Patch');
  if (f.serial_max) parts.push(`/${f.serial_max}`);
  if (f.is_rookie)  parts.push('RC');
  if (f.grade)      parts.push(f.grade);
  return parts.filter(Boolean).join(' ');
}

@Injectable({ providedIn: 'root' })
export class WishlistService {
  private auth = inject(AuthService);

  items = signal<WishlistItem[]>([]);
  loading = signal(false);
  triggeredCount = signal(0);

  private get apiUrl() { return environment.apiUrl; }

  private async headers(): Promise<Record<string, string>> {
    const session = await this.auth.getSession();
    return {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${session!.access_token}`,
    };
  }

  async load() {
    this.loading.set(true);
    try {
      const res = await fetch(`${this.apiUrl}/api/wishlist`, { headers: await this.headers() });
      if (res.ok) {
        const data = await res.json();
        this.items.set(data.map((i: any) => ({
          ...i,
          matches:             i.matches             ?? [],
          exclude_terms:       i.exclude_terms       ?? [],
          dismissed_ebay_ids:  i.dismissed_ebay_ids  ?? [],
        })));
      }
    } catch (e) {
      console.error('[WishlistService] load error:', e);
    } finally {
      this.loading.set(false);
    }
  }

  async checkNow(): Promise<{ checked: number; triggered: number; error?: string }> {
    try {
      const res = await fetch(`${this.apiUrl}/api/wishlist/check-now`, {
        method: 'POST',
        headers: await this.headers(),
      });
      if (!res.ok) {
        const { error } = await res.json();
        return { checked: 0, triggered: 0, error };
      }
      const result = await res.json();
      // Reload items + count so UI reflects any newly triggered items
      await Promise.all([this.load(), this.loadTriggeredCount()]);
      return result;
    } catch (e: any) {
      return { checked: 0, triggered: 0, error: e.message };
    }
  }

  async loadTriggeredCount() {
    try {
      const res = await fetch(`${this.apiUrl}/api/wishlist/triggered-count`, { headers: await this.headers() });
      if (res.ok) {
        const { count } = await res.json();
        this.triggeredCount.set(count ?? 0);
      }
    } catch {}
  }

  async add(data: WishlistFormData): Promise<{ error: string | null; item: WishlistItem | null }> {
    try {
      const res = await fetch(`${this.apiUrl}/api/wishlist`, {
        method: 'POST',
        headers: await this.headers(),
        body: JSON.stringify({
          player:        data.player || null,
          year:          data.year || null,
          set_name:      data.set_name || null,
          parallel:      data.parallel || null,
          card_number:   data.card_number || null,
          is_rookie:     data.is_rookie,
          is_auto:       data.is_auto,
          is_patch:      data.is_patch,
          serial_max:    data.serial_max || null,
          grade:         data.grade || null,
          ebay_query:    data.ebay_query || null,
          exclude_terms: data.exclude_terms ?? [],
          target_price:  data.target_price || null,
        }),
      });
      if (!res.ok) {
        const { error } = await res.json();
        return { error, item: null };
      }
      const item: WishlistItem = await res.json();
      this.items.update(list => [item, ...list]);
      return { error: null, item };
    } catch (e: any) {
      return { error: e.message, item: null };
    }
  }

  /** Full update for the edit flow — sends all form fields. */
  async patchAll(id: string, data: WishlistFormData): Promise<{ error: string | null }> {
    return this.patch(id, {
      player:        data.player || null,
      year:          data.year || null,
      set_name:      data.set_name || null,
      parallel:      data.parallel || null,
      card_number:   data.card_number || null,
      is_rookie:     data.is_rookie,
      is_auto:       data.is_auto,
      is_patch:      data.is_patch,
      serial_max:    data.serial_max || null,
      grade:         data.grade || null,
      ebay_query:    data.ebay_query || null,
      exclude_terms: data.exclude_terms ?? [],
      target_price:  data.target_price || null,
    } as any);
  }

  async patch(id: string, patch: Partial<Omit<WishlistItem, 'id' | 'created_at' | 'matches'>>): Promise<{ error: string | null }> {
    try {
      const res = await fetch(`${this.apiUrl}/api/wishlist/${id}`, {
        method: 'PATCH',
        headers: await this.headers(),
        body: JSON.stringify(patch),
      });
      if (!res.ok) {
        const { error } = await res.json();
        return { error };
      }
      const updated: WishlistItem = await res.json();
      this.items.update(list => list.map(i => i.id === id ? updated : i));
      return { error: null };
    } catch (e: any) {
      return { error: e.message };
    }
  }

  async dismissMatch(wishlistId: string, matchId: string): Promise<{ error: string | null }> {
    try {
      const res = await fetch(`${this.apiUrl}/api/wishlist/${wishlistId}/matches/${matchId}`, {
        method: 'DELETE',
        headers: await this.headers(),
      });
      if (!res.ok) return { error: 'Dismiss failed' };
      // Update local state: remove the match; if none left, reset status + price
      this.items.update(list => list.map(item => {
        if (item.id !== wishlistId) return item;
        const matches = item.matches.filter(m => m.id !== matchId);
        return {
          ...item,
          matches,
          alert_status:    matches.length === 0 ? 'active'     : item.alert_status,
          last_seen_price: matches.length === 0 ? null         : Math.min(...matches.map(m => m.price)),
        } as typeof item;
      }));
      return { error: null };
    } catch (e: any) {
      return { error: e.message };
    }
  }

  async remove(id: string): Promise<{ error: string | null }> {
    try {
      const res = await fetch(`${this.apiUrl}/api/wishlist/${id}`, {
        method: 'DELETE',
        headers: await this.headers(),
      });
      if (!res.ok) return { error: 'Delete failed' };
      this.items.update(list => list.filter(i => i.id !== id));
      return { error: null };
    } catch (e: any) {
      return { error: e.message };
    }
  }
}
