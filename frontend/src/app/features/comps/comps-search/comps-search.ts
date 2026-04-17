import { Component, inject, signal, computed, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink, ActivatedRoute } from '@angular/router';
import { Subscription } from 'rxjs';
import { AuthService } from '../../../core/services/auth';
import { environment } from '../../../../environments/environment';
import { AddToWishlistDialog, WishlistSeed } from '../../wishlist/add-to-wishlist-dialog/add-to-wishlist-dialog';
import { parseEbayTitle } from '../../../core/services/ebay-title-parser';


export interface SoldItem {
  itemId:       string | null;
  title:        string;
  price:        { value: string; currency: string };
  buyingOptions: string[];
  itemEndDate:  string | null;
  itemWebUrl:   string | null;
  imageUrl:     string | null;
  condition:    string;
}

export interface CompsStats {
  average_price: number;
  median_price:  number;
  min_price:     number;
  max_price:     number;
  total_results: number;
}

interface HistoryEntry {
  id:        string;
  query:     string;
  timestamp: string;
  results:   SoldItem[];
}

@Component({
  selector: 'app-comps-search',
  imports: [CommonModule, FormsModule, RouterLink, AddToWishlistDialog],
  templateUrl: './comps-search.html',
  styleUrl: './comps-search.scss',
})
export class CompsSearch implements OnInit, OnDestroy {
  private auth  = inject(AuthService);
  private route = inject(ActivatedRoute);
  private _qSub?: Subscription;

  query     = signal('');
  searching = signal(false);
  searched  = signal(false);
  error     = signal<string | null>(null);


  items = signal<SoldItem[]>([]);
  stats = signal<CompsStats | null>(null);

  readonly PAGE_SIZE = 10;
  page = signal(1);

  pagedItems = computed(() => {
    const start = (this.page() - 1) * this.PAGE_SIZE;
    return this.items().slice(start, start + this.PAGE_SIZE);
  });

  totalPages = computed(() => Math.max(1, Math.ceil(this.items().length / this.PAGE_SIZE)));

  history        = signal<HistoryEntry[]>([]);
  historyLoading = signal(false);

  // Wishlist add dialog
  showWishlistDialog = signal(false);
  wishlistSeed       = signal<WishlistSeed | null>(null);

  async ngOnInit() {
    await this.loadHistory();

    // Subscribe to query param changes so re-navigation (e.g. from wishlist)
    // triggers a new search even when the component is already alive.
    this._qSub = this.route.queryParamMap.subscribe(params => {
      const q = params.get('q');
      if (q?.trim()) {
        this.query.set(q.trim());
        this.search();
      }
    });
  }

  ngOnDestroy() {
    this._qSub?.unsubscribe();
  }

  async search() {
    const q = this.query().trim();
    if (!q || this.searching()) return;

    this.searching.set(true);
    this.error.set(null);
    this.searched.set(false);
    this.page.set(1);

    try {
      const session = await this.auth.getSession();
      const res = await fetch(`${environment.apiUrl}/api/comps/search`, {
        method:  'POST',
        headers: {
          'Content-Type':  'application/json',
          Authorization:   `Bearer ${session!.access_token}`,
        },
        body: JSON.stringify({ query: q }),
      });

      if (!res.ok) throw new Error(`Search failed (${res.status})`);

      const data = await res.json();
      this.items.set(data.items ?? []);
      this.stats.set(data.stats ?? null);
      this.searched.set(true);
      await this.loadHistory();
    } catch (e: any) {
      this.error.set(e.message ?? 'Search failed. Please try again.');
    } finally {
      this.searching.set(false);
    }
  }

  private async loadHistory() {
    this.historyLoading.set(true);
    try {
      const session = await this.auth.getSession();
      const res = await fetch(`${environment.apiUrl}/api/comps/history`, {
        headers: { Authorization: `Bearer ${session!.access_token}` },
      });
      if (res.ok) this.history.set(await res.json());
    } catch {}
    this.historyLoading.set(false);
  }

  rerun(entry: HistoryEntry) {
    this.query.set(entry.query);
    this.search();
  }

  historyTopPrice(entry: HistoryEntry): number {
    const prices = (entry.results ?? []).map(r => parseFloat(r.price?.value ?? '0')).filter(p => p > 0);
    return prices.length ? Math.max(...prices) : 0;
  }

  price(item: SoldItem): number {
    return parseFloat(item.price?.value ?? '0');
  }

  openWishlist(item: SoldItem) {
    this.wishlistSeed.set(parseEbayTitle(item.title, this.query(), this.price(item)));
    this.showWishlistDialog.set(true);
  }
}
