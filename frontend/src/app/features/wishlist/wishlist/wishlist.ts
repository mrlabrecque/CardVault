import { Component, inject, signal, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';
import { ButtonModule } from 'primeng/button';
import { TagModule } from 'primeng/tag';
import { WishlistService, WishlistItem, AlertStatus } from '../../../core/services/wishlist';
import { AddToWishlistDialog } from '../add-to-wishlist-dialog/add-to-wishlist-dialog';

@Component({
  selector: 'app-wishlist',
  imports: [CommonModule, ButtonModule, TagModule, AddToWishlistDialog],
  templateUrl: './wishlist.html',
  styleUrl: './wishlist.scss',
})
export class Wishlist implements OnInit {
  readonly wishlist = inject(WishlistService);
  private router = inject(Router);

  showAddDialog = signal(false);
  deletingId = signal<string | null>(null);

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

  searchComps(item: WishlistItem) {
    const q = item.ebay_query || item.player || '';
    this.router.navigate(['/comps'], { queryParams: { q } });
  }

  async togglePause(item: WishlistItem) {
    const next: AlertStatus = item.alert_status === 'paused' ? 'active' : 'paused';
    await this.wishlist.patch(item.id, { alert_status: next });
  }

  async removeItem(id: string) {
    this.deletingId.set(id);
    await this.wishlist.remove(id);
    this.deletingId.set(null);
  }

  attrs(item: WishlistItem): string[] {
    const tags: string[] = [];
    if (item.is_rookie) tags.push('RC');
    if (item.is_auto)   tags.push('AUTO');
    if (item.is_patch)  tags.push('PATCH');
    if (item.serial_max) tags.push(`/${item.serial_max}`);
    return tags;
  }
}
