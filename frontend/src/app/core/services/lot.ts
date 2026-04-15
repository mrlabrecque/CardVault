import { Injectable, signal, computed } from '@angular/core';
import { Card } from './cards';

@Injectable({ providedIn: 'root' })
export class LotService {
  readonly lotItems = signal<Card[]>([]);
  readonly pct = signal<number>(100);

  readonly lotItemIds = computed(() => new Set(this.lotItems().map(c => c.id)));

  readonly totalValue = computed(() =>
    this.lotItems().reduce((sum, c) => sum + c.currentValue, 0)
  );

  readonly askingPrice = computed(() =>
    this.totalValue() * this.pct() / 100
  );

  isInLot(cardId: string): boolean {
    return this.lotItemIds().has(cardId);
  }

  add(card: Card): void {
    if (!this.isInLot(card.id)) {
      this.lotItems.update(items => [...items, card]);
    }
  }

  remove(cardId: string): void {
    this.lotItems.update(items => items.filter(c => c.id !== cardId));
  }

  toggle(card: Card): void {
    this.isInLot(card.id) ? this.remove(card.id) : this.add(card);
  }

  clear(): void {
    this.lotItems.set([]);
    this.pct.set(100);
  }
}
