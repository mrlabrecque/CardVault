import { Component, inject } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { ActivatedRoute } from '@angular/router';
import { ButtonModule } from 'primeng/button';
import { CardsService, Card } from '../../../core/services/cards';
import { CardTags } from '../../../shared/card-tags/card-tags';

@Component({
  selector: 'app-item-detail',
  imports: [CommonModule, ButtonModule, CardTags],
  templateUrl: './item-detail.html',
  styleUrl: './item-detail.scss',
})
export class ItemDetail {
  private cardsService = inject(CardsService);
  private route = inject(ActivatedRoute);
  private location = inject(Location);

  card: Card | undefined;

  ngOnInit() {
    const id = this.route.snapshot.paramMap.get('id') ?? '';
    this.card = this.cardsService.getById(id);
  }

  goBack() { this.location.back(); }

  pl(): number {
    return this.card ? this.card.currentValue - this.card.pricePaid : 0;
  }

  sportIcon(sport: string): string {
    const map: Record<string, string> = {
      Football: '🏈', Hockey: '🏒', Basketball: '🏀', Baseball: '⚾',
    };
    return map[sport] ?? '🃏';
  }
}
