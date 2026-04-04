import { Component, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { ButtonModule } from 'primeng/button';
import { InputTextModule } from 'primeng/inputtext';
import { TagModule } from 'primeng/tag';

export interface Card {
  id: string;
  player: string;
  sport: string;
  set: string;
  year: number;
  variant: string;
  grade: string;
  pricePaid: number;
  currentValue: number;
}

@Component({
  selector: 'app-collection-list',
  imports: [CommonModule, FormsModule, RouterLink, ButtonModule, InputTextModule, TagModule],
  templateUrl: './collection-list.html',
  styleUrl: './collection-list.scss',
})
export class CollectionList {
  searchQuery = signal('');

  cards = signal<Card[]>([
    { id: '1', player: 'Patrick Mahomes', sport: 'Football', set: 'Panini Prizm', year: 2017, variant: 'Silver Prizm', grade: 'PSA 10', pricePaid: 600, currentValue: 1200 },
    { id: '2', player: 'Connor McDavid', sport: 'Hockey', set: 'Upper Deck Young Guns', year: 2015, variant: 'Base', grade: 'BGS 9.5', pricePaid: 750, currentValue: 980 },
    { id: '3', player: 'Luka Dončić', sport: 'Basketball', set: 'Panini Prizm', year: 2018, variant: 'Silver', grade: 'PSA 9', pricePaid: 500, currentValue: 740 },
    { id: '4', player: 'Ronald Acuña Jr.', sport: 'Baseball', set: 'Topps Chrome', year: 2018, variant: 'Refractor', grade: 'PSA 10', pricePaid: 300, currentValue: 560 },
    { id: '5', player: 'Josh Allen', sport: 'Football', set: 'Panini Optic', year: 2018, variant: 'Holo', grade: 'PSA 9', pricePaid: 280, currentValue: 410 },
    { id: '6', player: 'Nathan MacKinnon', sport: 'Hockey', set: 'Upper Deck', year: 2013, variant: 'Base', grade: 'PSA 10', pricePaid: 200, currentValue: 320 },
    { id: '7', player: 'Victor Wembanyama', sport: 'Basketball', set: 'Panini Prizm', year: 2023, variant: 'Gold Prizm', grade: 'PSA 10', pricePaid: 800, currentValue: 950 },
  ]);

  filtered = computed(() => {
    const q = this.searchQuery().toLowerCase();
    if (!q) return this.cards();
    return this.cards().filter(c =>
      c.player.toLowerCase().includes(q) ||
      c.set.toLowerCase().includes(q) ||
      c.sport.toLowerCase().includes(q)
    );
  });

  pl(card: Card): number {
    return card.currentValue - card.pricePaid;
  }

  plPercent(card: Card): string {
    const pct = ((card.currentValue - card.pricePaid) / card.pricePaid) * 100;
    return (pct >= 0 ? '+' : '') + pct.toFixed(0) + '%';
  }

  sportIcon(sport: string): string {
    const map: Record<string, string> = {
      Football: '🏈', Hockey: '🏒', Basketball: '🏀', Baseball: '⚾',
    };
    return map[sport] ?? '🃏';
  }
}
