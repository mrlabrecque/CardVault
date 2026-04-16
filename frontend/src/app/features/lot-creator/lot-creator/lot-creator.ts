import { Component, inject, signal, OnInit } from '@angular/core';
import { RouterLink } from '@angular/router';
import { CardsService } from '../../../core/services/cards';
import { LotService } from '../../../core/services/lot';
import { LotCardPicker } from '../lot-card-picker/lot-card-picker';
import { LotBasket } from '../lot-basket/lot-basket';

@Component({
  selector: 'app-lot-creator',
  standalone: true,
  imports: [RouterLink, LotCardPicker, LotBasket],
  templateUrl: './lot-creator.html',
  styleUrl: './lot-creator.scss',
})
export class LotCreator implements OnInit {
  private cardsService = inject(CardsService);
  readonly lot = inject(LotService);

  view = signal<'picker' | 'basket'>('picker');

  ngOnInit() {
    if (this.cardsService.cards().length === 0) {
      this.cardsService.loadUserCards();
    }
  }
}
