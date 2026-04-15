import { Injectable, inject, signal } from '@angular/core';
import { AuthService } from './auth';
import { environment } from '../../../environments/environment';

export type AlertStatus = 'active' | 'paused' | 'triggered';

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
  target_price: number | null;
  alert_status: AlertStatus;
  last_seen_price: number | null;
  last_checked_at: string | null;
  created_at: string;
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
  target_price: number | null;
}

/** Build a sensible eBay search query from form fields. */
export function buildEbayQuery(f: Pick<WishlistFormData, 'player' | 'year' | 'set_name' | 'parallel' | 'grade' | 'serial_max' | 'is_rookie' | 'is_auto'>): string {
  const parts: string[] = [];
  if (f.player)    parts.push(f.player);
  if (f.year)      parts.push(String(f.year));
  if (f.set_name)  parts.push(f.set_name);
  if (f.parallel && f.parallel.toLowerCase() !== 'base') parts.push(f.parallel);
  if (f.is_rookie) parts.push('RC');
  if (f.is_auto)   parts.push('Auto');
  if (f.serial_max) parts.push(`/${f.serial_max}`);
  if (f.grade)     parts.push(f.grade);
  return parts.join(' ');
}

@Injectable({ providedIn: 'root' })
export class WishlistService {
  private auth = inject(AuthService);

  items = signal<WishlistItem[]>([]);
  loading = signal(false);

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
      if (res.ok) this.items.set(await res.json());
    } catch (e) {
      console.error('[WishlistService] load error:', e);
    } finally {
      this.loading.set(false);
    }
  }

  async add(data: WishlistFormData): Promise<{ error: string | null; item: WishlistItem | null }> {
    try {
      const res = await fetch(`${this.apiUrl}/api/wishlist`, {
        method: 'POST',
        headers: await this.headers(),
        body: JSON.stringify({
          player:      data.player || null,
          year:        data.year || null,
          set_name:    data.set_name || null,
          parallel:    data.parallel || null,
          card_number: data.card_number || null,
          is_rookie:   data.is_rookie,
          is_auto:     data.is_auto,
          is_patch:    data.is_patch,
          serial_max:  data.serial_max || null,
          grade:       data.grade || null,
          ebay_query:  data.ebay_query || null,
          target_price: data.target_price || null,
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

  async patch(id: string, patch: Partial<Pick<WishlistItem, 'target_price' | 'ebay_query' | 'alert_status'>>): Promise<{ error: string | null }> {
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
