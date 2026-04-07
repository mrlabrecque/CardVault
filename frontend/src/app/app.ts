import { Component, signal, computed, inject, effect } from '@angular/core';
import { Router, RouterOutlet, RouterLink, RouterLinkActive, NavigationEnd } from '@angular/router';
import { toSignal } from '@angular/core/rxjs-interop';
import { filter, map, startWith } from 'rxjs';
import { AuthService } from './core/services/auth';
import { UiService } from './core/services/ui';
import { ReleasesService } from './core/services/releases';
import { AddCardDialog } from './features/collection/add-card-dialog/add-card-dialog';

const PAGE_TITLES: Record<string, string> = {
  dashboard:  'Dashboard',
  collection: 'Collection',
  comps:      'Comp Search',
  wishlist:   'Wishlist',
  scanner:    'Scan Cards',
  'bulk-add': 'Bulk Add',
  admin:      'Manage Releases',
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
  readonly ui = inject(UiService);
  private releasesService = inject(ReleasesService);

  initials = computed(() => (this.auth.user()?.email ?? '').charAt(0).toUpperCase());

  pageTitle!: ReturnType<typeof toSignal<string>>;

  constructor(readonly auth: AuthService, private router: Router) {
    this.pageTitle = toSignal(
      this.router.events.pipe(
        filter(e => e instanceof NavigationEnd),
        map(() => this.titleFromUrl()),
        startWith(this.titleFromUrl())
      ),
      { initialValue: this.titleFromUrl() }
    );

    effect(() => {
      if (this.auth.isAppAdmin()) {
        this.releasesService.getPendingCount().then(n => this.pendingParallelCount.set(n));
      } else {
        this.pendingParallelCount.set(0);
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
