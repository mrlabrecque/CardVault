import { Component, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ButtonModule } from 'primeng/button';
import { TagModule } from 'primeng/tag';
import { InputNumberModule } from 'primeng/inputnumber';

export type AlertStatus = 'active' | 'triggered' | 'paused';

export interface WishlistItem {
  id: string;
  player: string;
  set: string;
  year: number;
  variant: string;
  grade: string;
  targetPrice: number;
  lastSeenPrice: number | null;
  alertStatus: AlertStatus;
}

@Component({
  selector: 'app-wishlist',
  imports: [CommonModule, FormsModule, ButtonModule, TagModule, InputNumberModule],
  templateUrl: './wishlist.html',
  styleUrl: './wishlist.scss',
})
export class Wishlist {
  items = signal<WishlistItem[]>([
    { id: '1', player: 'Auston Matthews', set: 'Upper Deck Young Guns', year: 2016, variant: 'Base', grade: 'PSA 10', targetPrice: 400, lastSeenPrice: 520, alertStatus: 'active' },
    { id: '2', player: 'Caitlin Clark', set: 'Topps Chrome', year: 2024, variant: 'Refractor', grade: 'PSA 10', targetPrice: 300, lastSeenPrice: 295, alertStatus: 'triggered' },
    { id: '3', player: 'Jayden Daniels', set: 'Panini Prizm', year: 2024, variant: 'Silver', grade: 'PSA 10', targetPrice: 150, lastSeenPrice: null, alertStatus: 'paused' },
    { id: '4', player: 'Sam Bennett', set: 'Upper Deck', year: 2014, variant: 'Base', grade: 'PSA 9', targetPrice: 80, lastSeenPrice: 95, alertStatus: 'active' },
  ]);

  statusLabel: Record<AlertStatus, string> = {
    active: 'Watching',
    triggered: 'Below Target!',
    paused: 'Paused',
  };

  statusSeverity: Record<AlertStatus, 'success' | 'warn' | 'secondary'> = {
    active: 'success',
    triggered: 'warn',
    paused: 'secondary',
  };

  removeItem(id: string) {
    this.items.update(items => items.filter(i => i.id !== id));
  }
}
