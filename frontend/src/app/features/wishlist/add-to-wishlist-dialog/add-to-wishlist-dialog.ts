import { Component, inject, input, output, signal, effect, untracked } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { InputNumberModule } from 'primeng/inputnumber';
import { WishlistService, WishlistFormData, buildEbayQuery } from '../../../core/services/wishlist';

/** Seed data passed in when opening from Comps (all fields optional). */
export interface WishlistSeed {
  player?: string;
  year?: number | null;
  set_name?: string;
  parallel?: string;
  card_number?: string;
  is_rookie?: boolean;
  is_auto?: boolean;
  is_patch?: boolean;
  serial_max?: number | null;
  grade?: string;
  suggested_price?: number | null;
}

@Component({
  selector: 'app-add-to-wishlist-dialog',
  imports: [CommonModule, FormsModule, InputNumberModule],
  templateUrl: './add-to-wishlist-dialog.html',
})
export class AddToWishlistDialog {
  private wishlist = inject(WishlistService);

  visible = input<boolean>(false);
  seed    = input<WishlistSeed | null>(null);

  visibleChange = output<boolean>();
  added         = output<void>();

  saving = signal(false);
  error  = signal<string | null>(null);

  // Form fields
  player       = signal('');
  year         = signal<number | null>(null);
  set_name     = signal('');
  parallel     = signal('');
  card_number  = signal('');
  is_rookie    = signal(false);
  is_auto      = signal(false);
  is_patch     = signal(false);
  serial_max   = signal<number | null>(null);
  grade        = signal('');
  ebay_query   = signal('');
  target_price = signal<number | null>(null);

  ebayQueryEdited = signal(false);

  constructor() {
    // When the dialog opens, populate from seed (using untracked to avoid
    // signal-write-inside-effect warnings — same pattern as add-card-dialog).
    effect(() => {
      if (!this.visible()) return;
      const s = this.seed();
      untracked(() => {
        this.player.set(s?.player ?? '');
        this.year.set(s?.year ?? null);
        this.set_name.set(s?.set_name ?? '');
        this.parallel.set(s?.parallel ?? '');
        this.card_number.set(s?.card_number ?? '');
        this.is_rookie.set(s?.is_rookie ?? false);
        this.is_auto.set(s?.is_auto ?? false);
        this.is_patch.set(s?.is_patch ?? false);
        this.serial_max.set(s?.serial_max ?? null);
        this.grade.set(s?.grade ?? '');
        this.target_price.set(s?.suggested_price ?? null);
        this.ebayQueryEdited.set(false);
        this.error.set(null);
        this.rebuildQuery();
      });
    });
  }

  rebuildQuery() {
    if (this.ebayQueryEdited()) return;
    this.ebay_query.set(buildEbayQuery({
      player:    this.player(),
      year:      this.year(),
      set_name:  this.set_name(),
      parallel:  this.parallel(),
      grade:     this.grade(),
      serial_max: this.serial_max(),
      is_rookie: this.is_rookie(),
      is_auto:   this.is_auto(),
    }));
  }

  onQueryInput(val: string) {
    this.ebay_query.set(val);
    this.ebayQueryEdited.set(true);
  }

  toggleAttr(attr: 'is_rookie' | 'is_auto' | 'is_patch') {
    if (attr === 'is_rookie') this.is_rookie.update(v => !v);
    if (attr === 'is_auto')   this.is_auto.update(v => !v);
    if (attr === 'is_patch')  this.is_patch.update(v => !v);
    this.rebuildQuery();
  }

  close() {
    this.visibleChange.emit(false);
  }

  async save() {
    if (!this.player().trim()) {
      this.error.set('Player name is required.');
      return;
    }
    this.saving.set(true);
    this.error.set(null);

    const data: WishlistFormData = {
      player:       this.player().trim(),
      year:         this.year(),
      set_name:     this.set_name().trim(),
      parallel:     this.parallel().trim(),
      card_number:  this.card_number().trim(),
      is_rookie:    this.is_rookie(),
      is_auto:      this.is_auto(),
      is_patch:     this.is_patch(),
      serial_max:   this.serial_max(),
      grade:        this.grade().trim(),
      ebay_query:   this.ebay_query().trim(),
      target_price: this.target_price(),
    };

    const { error } = await this.wishlist.add(data);
    this.saving.set(false);

    if (error) {
      this.error.set(error);
    } else {
      this.added.emit();
      this.close();
    }
  }
}
