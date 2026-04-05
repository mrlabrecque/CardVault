import { Component, inject, signal } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { ActivatedRoute, Router } from '@angular/router';
import { ButtonModule } from 'primeng/button';
import { CardsService, Card, SoldComp } from '../../../core/services/cards';
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
  private router = inject(Router);
  private location = inject(Location);

  card: Card | undefined;
  comps = signal<SoldComp[]>([]);
  compsLoading = signal(false);
  confirmingDelete = signal(false);
  deleting = signal(false);

  async ngOnInit() {
    const id = this.route.snapshot.paramMap.get('id') ?? '';
    this.card = this.cardsService.getById(id);
    if (id) {
      this.compsLoading.set(true);
      this.comps.set(await this.cardsService.fetchCardComps(id));
      this.compsLoading.set(false);
    }
  }

  goBack() { this.location.back(); }

  async confirmDelete() {
    if (!this.card) return;
    this.deleting.set(true);
    const { error } = await this.cardsService.deleteCard(this.card.id);
    this.deleting.set(false);
    if (!error) {
      this.router.navigate(['/collection']);
    }
  }

  pl(): number {
    return this.card ? this.card.currentValue - this.card.pricePaid : 0;
  }

  sportIcon(sport: string): string {
    const map: Record<string, string> = {
      Football: '🏈', Hockey: '🏒', Basketball: '🏀', Baseball: '⚾',
    };
    return map[sport] ?? '🃏';
  }

  saleTypeLabel(comp: SoldComp): string {
    const labels: Record<SoldComp['sale_type'], string> = {
      auction:     'Auction',
      fixed_price: 'Buy It Now',
      best_offer:  'Best Offer',
    };
    return labels[comp.sale_type];
  }

  saleTypeClasses(comp: SoldComp): string {
    const cls: Record<SoldComp['sale_type'], string> = {
      auction:     'bg-blue-50 text-blue-700',
      fixed_price: 'bg-green-50 text-green-700',
      best_offer:  'bg-amber-50 text-amber-700',
    };
    return cls[comp.sale_type];
  }
}
