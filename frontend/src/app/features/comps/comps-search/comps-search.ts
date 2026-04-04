import { Component, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ButtonModule } from 'primeng/button';
import { InputTextModule } from 'primeng/inputtext';
import { TagModule } from 'primeng/tag';

interface CompResult {
  title: string;
  price: number;
  condition: string;
  soldDate: string;
  platform: string;
}

interface LookupEntry {
  query: string;
  timestamp: Date;
  topPrice: number;
}

@Component({
  selector: 'app-comps-search',
  imports: [CommonModule, FormsModule, ButtonModule, InputTextModule, TagModule],
  templateUrl: './comps-search.html',
  styleUrl: './comps-search.scss',
})
export class CompsSearch {
  query = signal('');
  hasSearched = signal(false);

  results = signal<CompResult[]>([
    { title: 'Patrick Mahomes 2017 Panini Prizm Silver PSA 10', price: 1249.99, condition: 'PSA 10', soldDate: '2026-04-01', platform: 'eBay' },
    { title: 'Patrick Mahomes 2017 Panini Prizm Silver PSA 10', price: 1175.00, condition: 'PSA 10', soldDate: '2026-03-29', platform: 'eBay' },
    { title: 'Mahomes 2017 Prizm Silver RC PSA 10', price: 1300.00, condition: 'PSA 10', soldDate: '2026-03-27', platform: 'eBay' },
    { title: 'Patrick Mahomes 2017 Prizm Silver PSA 9', price: 420.00, condition: 'PSA 9', soldDate: '2026-03-25', platform: 'eBay' },
    { title: 'Patrick Mahomes Prizm RC Silver Rookie 2017', price: 389.00, condition: 'Ungraded', soldDate: '2026-03-22', platform: 'eBay' },
  ]);

  history = signal<LookupEntry[]>([
    { query: 'Mahomes 2017 Prizm Silver PSA 10', timestamp: new Date('2026-04-03T18:22:00'), topPrice: 1300 },
    { query: 'McDavid Young Guns BGS 9.5', timestamp: new Date('2026-04-02T10:05:00'), topPrice: 980 },
    { query: 'Luka Doncic Prizm Silver PSA 9', timestamp: new Date('2026-04-01T14:30:00'), topPrice: 740 },
    { query: 'Wembanyama Prizm Gold PSA 10', timestamp: new Date('2026-03-31T09:15:00'), topPrice: 950 },
  ]);

  search() {
    if (!this.query().trim()) return;
    this.hasSearched.set(true);
  }

  addToCollection(result: CompResult) {
    // TODO: open add-to-collection dialog
  }

  addToWishlist(result: CompResult) {
    // TODO: add to wishlist
  }
}
