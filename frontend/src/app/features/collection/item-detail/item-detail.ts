import { Component } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { ButtonModule } from 'primeng/button';
import { TagModule } from 'primeng/tag';

@Component({
  selector: 'app-item-detail',
  imports: [CommonModule, ButtonModule, TagModule],
  templateUrl: './item-detail.html',
  styleUrl: './item-detail.scss',
})
export class ItemDetail {
  // TODO: load card by route param
  card = {
    player: 'Patrick Mahomes',
    sport: 'Football',
    set: 'Panini Prizm',
    year: 2017,
    variant: 'Silver Prizm',
    grade: 'PSA 10',
    pricePaid: 600,
    currentValue: 1200,
  };

  constructor(private location: Location) {}

  goBack() { this.location.back(); }
}
