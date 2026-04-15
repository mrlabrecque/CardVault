import { Component, inject, input, output, signal, effect, untracked } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { InputNumberModule } from 'primeng/inputnumber';
import { WishlistService, WishlistFormData, buildEbayQuery } from '../../../core/services/wishlist';

/** Seed data passed in when opening from Comps or for editing an existing item. */
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
  ebay_query?: string;
  exclude_terms?: string[];
  suggested_price?: number | null;
}

@Component({
  selector: 'app-add-to-wishlist-dialog',
  imports: [CommonModule, FormsModule, InputNumberModule],
  templateUrl: './add-to-wishlist-dialog.html',
})
export class AddToWishlistDialog {
  private wishlist = inject(WishlistService);

  visible  = input<boolean>(false);
  seed     = input<WishlistSeed | null>(null);
  /** When true: Save button emits `saved` with form data instead of calling add(). */
  editMode = input<boolean>(false);

  visibleChange = output<boolean>();
  /** Emitted in add mode after successful save. */
  added  = output<void>();
  /** Emitted in edit mode — parent is responsible for calling patchAll(). */
  saved  = output<WishlistFormData>();

  saving = signal(false);
  error  = signal<string | null>(null);

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
  ebay_query      = signal('');
  exclude_terms   = signal<string[]>([]);
  target_price    = signal<number | null>(null);
  ebayQueryEdited = signal(false);
  excludeInput    = signal('');

  constructor() {
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
        this.exclude_terms.set(s?.exclude_terms ? [...s.exclude_terms] : []);
        this.excludeInput.set('');
        this.target_price.set(s?.suggested_price ?? null);
        this.error.set(null);
        // In edit mode, populate the existing query and mark it as user-edited
        // so it doesn't get auto-rebuilt on every keystroke.
        if (s?.ebay_query) {
          this.ebay_query.set(s.ebay_query);
          this.ebayQueryEdited.set(true);
        } else {
          this.ebayQueryEdited.set(false);
          this.rebuildQuery();
        }
      });
    });
  }

  rebuildQuery() {
    if (this.ebayQueryEdited()) return;
    this.ebay_query.set(buildEbayQuery({
      player:     this.player(),
      year:       this.year(),
      set_name:   this.set_name(),
      parallel:   this.parallel(),
      grade:      this.grade(),
      serial_max: this.serial_max(),
      is_rookie:  this.is_rookie(),
      is_auto:    this.is_auto(),
    }));
  }

  onQueryInput(val: string) {
    this.ebay_query.set(val);
    this.ebayQueryEdited.set(true);
  }

  addExcludeTerm(event: KeyboardEvent) {
    if (event.key !== 'Enter' && event.key !== ',') return;
    event.preventDefault();
    const term = this.excludeInput().trim().replace(/^,+|,+$/g, '');
    if (!term) return;
    if (!this.exclude_terms().includes(term)) {
      this.exclude_terms.update(list => [...list, term]);
    }
    this.excludeInput.set('');
  }

  removeExcludeTerm(term: string) {
    this.exclude_terms.update(list => list.filter(t => t !== term));
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

    const data: WishlistFormData = {
      player:        this.player().trim(),
      year:          this.year(),
      set_name:      this.set_name().trim(),
      parallel:      this.parallel().trim(),
      card_number:   this.card_number().trim(),
      is_rookie:     this.is_rookie(),
      is_auto:       this.is_auto(),
      is_patch:      this.is_patch(),
      serial_max:    this.serial_max(),
      grade:         this.grade().trim(),
      ebay_query:    this.ebay_query().trim(),
      exclude_terms: this.exclude_terms(),
      target_price:  this.target_price(),
    };

    if (this.editMode()) {
      // Edit mode — emit data up, parent handles the patch
      this.saved.emit(data);
      return;
    }

    // Add mode — call service directly
    this.saving.set(true);
    this.error.set(null);
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
