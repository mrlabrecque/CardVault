import { Component, inject, signal } from '@angular/core';
import { CommonModule, Location } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { ButtonModule } from 'primeng/button';
import { CardsService, Card, SoldComp } from '../../../core/services/cards';
import { ReleasesService, SetParallel } from '../../../core/services/releases';
import { CardTags } from '../../../shared/card-tags/card-tags';

const GRADERS = ['PSA', 'BGS', 'SGC', 'CGC', 'CSG'];

@Component({
  selector: 'app-item-detail',
  imports: [CommonModule, FormsModule, ButtonModule, CardTags],
  templateUrl: './item-detail.html',
  styleUrl: './item-detail.scss',
})
export class ItemDetail {
  private cardsService = inject(CardsService);
  private releasesService = inject(ReleasesService);
  private route = inject(ActivatedRoute);
  private router = inject(Router);
  private location = inject(Location);

  readonly graders = GRADERS;

  card: Card | undefined;
  comps = signal<SoldComp[]>([]);
  compsLoading = signal(false);
  confirmingDelete = signal(false);
  deleting = signal(false);

  // Edit state
  editing = signal(false);
  saving = signal(false);
  parallels = signal<SetParallel[]>([]);

  editPricePaid = signal<number | null>(null);
  editSerialNumber = signal('');
  editIsGraded = signal(false);
  editGrader = signal('PSA');
  editGradeValue = signal('');
  editParallelId = signal<string | null>(null);
  editParallelName = signal('Base');
  editOtherParallel = signal('');

  get isOtherParallel(): boolean {
    return this.editParallelId() === '__other__';
  }

  async ngOnInit() {
    const id = this.route.snapshot.paramMap.get('id') ?? '';
    this.card = this.cardsService.getById(id);
    if (id) {
      this.compsLoading.set(true);
      this.comps.set(await this.cardsService.fetchCardComps(id));
      this.compsLoading.set(false);
    }
    if (this.card?.setId) {
      this.parallels.set(await this.releasesService.getParallels(this.card.setId));
    }
  }

  startEdit() {
    if (!this.card) return;
    this.editPricePaid.set(this.card.pricePaid || null);
    this.editSerialNumber.set(this.card.serialNumber ?? '');
    this.editIsGraded.set(this.card.isGraded);
    this.editGrader.set(this.card.grader ?? 'PSA');
    this.editGradeValue.set(this.card.gradeValue ?? '');
    // Resolve parallel: find matching id in loaded parallels, or treat as "other"
    const matched = this.parallels().find(p => p.name === this.card!.parallel.replace(/ \/\d+$/, ''));
    if (matched) {
      this.editParallelId.set(matched.id);
      this.editParallelName.set(matched.name);
    } else if (this.card.parallel === 'Base') {
      this.editParallelId.set(null);
      this.editParallelName.set('Base');
    } else {
      this.editParallelId.set('__other__');
      this.editOtherParallel.set(this.card.parallel);
    }
    this.editing.set(true);
  }

  cancelEdit() {
    this.editing.set(false);
  }

  onParallelChange(id: string | null) {
    this.editParallelId.set(id);
    if (id === null) {
      this.editParallelName.set('Base');
    } else if (id !== '__other__') {
      const p = this.parallels().find(p => p.id === id);
      if (p) this.editParallelName.set(p.name);
    }
  }

  async saveEdit() {
    if (!this.card) return;
    this.saving.set(true);

    const parallelId = this.isOtherParallel ? null : this.editParallelId();
    const parallelName = this.isOtherParallel
      ? (this.editOtherParallel().trim() || 'Base')
      : this.editParallelName();

    const { error } = await this.cardsService.updateCard(this.card.id, {
      pricePaid:    this.editPricePaid(),
      serialNumber: this.card.serialMax ? this.editSerialNumber() : null,
      isGraded:     this.editIsGraded(),
      grader:       this.editIsGraded() ? this.editGrader() : null,
      gradeValue:   this.editIsGraded() ? this.editGradeValue() : null,
      parallelId,
      parallelName,
    });

    this.saving.set(false);
    if (!error) {
      this.card = this.cardsService.getById(this.card.id);
      this.editing.set(false);
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

  serialLabel(card: Card): string | null {
    if (card.serialNumber && card.serialMax) return `${card.serialNumber}/${card.serialMax}`;
    if (card.serialNumber) return card.serialNumber;
    if (card.serialMax) return `/${card.serialMax}`;
    return null;
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
