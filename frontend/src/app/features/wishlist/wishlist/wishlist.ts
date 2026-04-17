import { Component, inject, signal, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { ButtonModule } from 'primeng/button';
import { TagModule } from 'primeng/tag';
import { WishlistService, WishlistItem, WishlistFormData, AlertStatus } from '../../../core/services/wishlist';
import { AddToWishlistDialog, WishlistSeed } from '../add-to-wishlist-dialog/add-to-wishlist-dialog';

@Component({
  selector: 'app-wishlist',
  imports: [CommonModule, ButtonModule, TagModule, AddToWishlistDialog],
  templateUrl: './wishlist.html',
  styleUrl: './wishlist.scss',
})
export class Wishlist implements OnInit {
  readonly wishlist = inject(WishlistService);
  private router = inject(Router);

  showAddDialog  = signal(false);
  editingItem    = signal<WishlistItem | null>(null);
  editSeed       = signal<WishlistSeed | null>(null);
  deletingId     = signal<string | null>(null);
  checking       = signal(false);
  checkResult    = signal<{ checked: number; triggered: number } | null>(null);

  // Track which items have their matches expanded (by id)
  expandedMatches = signal<Set<string>>(new Set());

  statusLabel: Record<AlertStatus, string> = {
    active:    'Watching',
    triggered: 'Below Target!',
    paused:    'Paused',
  };

  statusSeverity: Record<AlertStatus, 'success' | 'warn' | 'secondary'> = {
    active:    'success',
    triggered: 'warn',
    paused:    'secondary',
  };

  async ngOnInit() {
    await this.wishlist.load();
  }

  async checkNow() {
    if (this.checking()) return;
    this.checking.set(true);
    this.checkResult.set(null);
    const result = await this.wishlist.checkNow();
    this.checking.set(false);
    if (!result.error) this.checkResult.set(result);
  }

  /** Most recent last_checked_at across all items — reflects cron job runs too. */
  lastCheckedAt(): string | null {
    const timestamps = this.wishlist.items()
      .map(i => i.last_checked_at)
      .filter(Boolean) as string[];
    if (!timestamps.length) return null;
    return timestamps.reduce((latest, t) => (t > latest ? t : latest));
  }

  formatLastChecked(): string | null {
    const iso = this.lastCheckedAt();
    if (!iso) return null;
    const date = new Date(iso);
    const now = new Date();
    const isToday = date.toDateString() === now.toDateString();
    const time = date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    if (isToday) return time;
    return date.toLocaleDateString([], { month: 'short', day: 'numeric' }) + ' at ' + time;
  }

  searchComps(item: WishlistItem) {
    const base = item.ebay_query || item.player || '';
    const exclusions = (item.exclude_terms ?? []).map(t => `-"${t}"`).join(' ');
    const q = exclusions ? `${base} ${exclusions}` : base;
    this.router.navigate(['/comps'], { queryParams: { q } });
  }

  async togglePause(item: WishlistItem) {
    const next: AlertStatus = item.alert_status === 'paused' ? 'active' : 'paused';
    await this.wishlist.patch(item.id, { alert_status: next });
    await this.wishlist.loadTriggeredCount();
  }

  async removeItem(id: string) {
    this.deletingId.set(id);
    await this.wishlist.remove(id);
    this.deletingId.set(null);
    await this.wishlist.loadTriggeredCount();
  }

  openEdit(item: WishlistItem) {
    this.editingItem.set(item);
    this.editSeed.set({
      player:          item.player ?? '',
      year:            item.year,
      set_name:        item.set_name ?? '',
      parallel:        item.parallel ?? '',
      card_number:     item.card_number ?? '',
      is_rookie:       item.is_rookie,
      is_auto:         item.is_auto,
      is_patch:        item.is_patch,
      serial_max:      item.serial_max,
      grade:           item.grade ?? '',
      ebay_query:      item.ebay_query ?? '',
      exclude_terms:   item.exclude_terms ?? [],
      suggested_price: item.target_price,
    });
    this.showAddDialog.set(true);
  }

  closeDialog() {
    this.showAddDialog.set(false);
    this.editingItem.set(null);
    this.editSeed.set(null);
  }

  async onDialogSaved(data: WishlistFormData) {
    const editing = this.editingItem();
    if (editing) {
      // Patch the existing item instead of creating a new one
      await this.wishlist.patchAll(editing.id, data);
    }
    // If not editing, the dialog already called add() internally — just reload
    await this.wishlist.load();
    await this.wishlist.loadTriggeredCount();
    this.closeDialog();
  }

  async dismissMatch(item: WishlistItem, match: { id: string }) {
    await this.wishlist.dismissMatch(item.id, match.id);
    await this.wishlist.loadTriggeredCount();
  }

  toggleMatches(id: string) {
    this.expandedMatches.update(set => {
      const next = new Set(set);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  }

  isMatchesExpanded(id: string): boolean {
    return this.expandedMatches().has(id);
  }

  attrs(item: WishlistItem): string[] {
    const tags: string[] = [];
    if (item.is_rookie)  tags.push('RC');
    if (item.is_auto)    tags.push('AUTO');
    if (item.is_patch)   tags.push('PATCH');
    if (item.serial_max) tags.push(`/${item.serial_max}`);
    return tags;
  }

  isBelowTarget(item: WishlistItem): boolean {
    return item.alert_status === 'triggered';
  }

  savings(item: WishlistItem): number {
    if (!item.last_seen_price || !item.target_price) return 0;
    return item.target_price - item.last_seen_price;
  }
}
