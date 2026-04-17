import { Component, signal, computed, inject, effect } from '@angular/core';
import { Router, RouterOutlet, RouterLink, RouterLinkActive, NavigationEnd, NavigationStart, NavigationCancel, NavigationError } from '@angular/router';
import { toSignal } from '@angular/core/rxjs-interop';
import { filter, map, startWith } from 'rxjs';
import { AuthService } from './core/services/auth';
import { UiService } from './core/services/ui';
import { ReleasesService } from './core/services/releases';
import { WishlistService } from './core/services/wishlist';
import { AddCardDialog } from './features/collection/add-card-dialog/add-card-dialog';

const PAGE_TITLES: Record<string, string> = {
  dashboard:  'Dashboard',
  collection: 'Collection',
  comps:      'Comp Search',
  wishlist:   'Wishlist',
  tools:      'Tools',
  scanner:    'Scan Cards',
  'bulk-add':    'Bulk Add',
  'lot-creator': 'Lot Creator',
  admin:         'Manage Releases',
};

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, RouterLink, RouterLinkActive, AddCardDialog],
  templateUrl: './app.html',
  styleUrl: './app.scss'
})
export class App {
  menuOpen = signal(false);
  pendingParallelCount = signal(0);
  isNavigating = signal(false);
  showNavigatingSpinner = signal(false);
  private _navSpinnerTimer: ReturnType<typeof setTimeout> | null = null;
  readonly ui = inject(UiService);
  readonly wishlistService = inject(WishlistService);
  private releasesService = inject(ReleasesService);

  initials = computed(() => (this.auth.user()?.email ?? '').charAt(0).toUpperCase());

  pageTitle!: ReturnType<typeof toSignal<string>>;

  constructor(readonly auth: AuthService, private router: Router) {
    this.pageTitle = toSignal(
      this.router.events.pipe(
        filter(e => e instanceof NavigationEnd),
        map(() => {
          document.getElementById('app-content')?.scrollTo({ top: 0, behavior: 'instant' });
          return this.titleFromUrl();
        }),
        startWith(this.titleFromUrl())
      ),
      { initialValue: this.titleFromUrl() }
    );

    this.router.events.subscribe(e => {
      if (e instanceof NavigationStart) {
        this.isNavigating.set(true);
        this._navSpinnerTimer = setTimeout(() => {
          if (this.isNavigating()) this.showNavigatingSpinner.set(true);
        }, 150);
      }
      if (e instanceof NavigationEnd || e instanceof NavigationCancel || e instanceof NavigationError) {
        this.isNavigating.set(false);
        this.showNavigatingSpinner.set(false);
        if (this._navSpinnerTimer) { clearTimeout(this._navSpinnerTimer); this._navSpinnerTimer = null; }
      }
    });

    effect(() => {
      if (this.auth.isAppAdmin()) {
        this.releasesService.getPendingCount().then(n => this.pendingParallelCount.set(n));
      } else {
        this.pendingParallelCount.set(0);
      }
    });

    effect(() => {
      if (this.auth.isAuthenticated()) {
        this.wishlistService.loadTriggeredCount();
      } else {
        this.wishlistService.triggeredCount.set(0);
      }
    });
  }

  private titleFromUrl(): string {
    const segment = this.router.url.split('/')[1]?.split('?')[0] ?? '';
    return PAGE_TITLES[segment] ?? 'Card Vault';
  }

  toggleMenu() { this.menuOpen.update(v => !v); }

  async signOut() {
    this.menuOpen.set(false);
    await this.auth.signOut();
  }
}
