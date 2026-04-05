import { Component, inject, signal, effect, Output, EventEmitter } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { CardsService, MasterCard } from '../../../core/services/cards';
import { SetsService, SetRecord, SetParallel } from '../../../core/services/sets';
import { UiService } from '../../../core/services/ui';

const GRADERS = ['PSA', 'BGS', 'SGC', 'CGC', 'CSG'];
const FALLBACK_PARALLELS = ['Base', 'Silver Prizm', 'Gold Prizm', 'Red Prizm', 'Blue Prizm', 'Holo', 'Refractor', 'Gold Refractor', 'Xfractor', 'Rookie Patch Auto'];

@Component({
  selector: 'app-add-card-dialog',
  imports: [CommonModule, FormsModule],
  templateUrl: './add-card-dialog.html',
  styleUrl: './add-card-dialog.scss',
})
export class AddCardDialog {
  private cardsService = inject(CardsService);
  private setsService = inject(SetsService);
  private ui = inject(UiService);

  @Output() cardAdded = new EventEmitter<void>();

  readonly graders = GRADERS;
  readonly fallbackParallels = FALLBACK_PARALLELS;

  // Parallels loaded for the selected set
  setParallels = signal<SetParallel[]>([]);
  // true when user has picked "Other…" from the set-driven dropdown
  parallelIsOther = signal(false);

  // Visibility driven by shared UiService so any part of the shell can open it
  readonly visible = this.ui.addCardOpen;
  saving = signal(false);

  constructor() {
    // Reset form state whenever the dialog is opened
    effect(() => { if (this.ui.addCardOpen()) this.reset(); });
  }
  saveError = signal<string | null>(null);

  // Step 1: Set search
  setQuery = signal('');
  setResults = signal<SetRecord[]>([]);
  showSetDropdown = signal(false);
  selectedSet = signal<SetRecord | null>(null);

  // Step 2: Card search
  cardQuery = signal('');
  cardResults = signal<MasterCard[]>([]);
  showCardDropdown = signal(false);
  selectedMasterCard = signal<MasterCard | null>(null);
  isNewCard = signal(false);
  noCardResults = signal(false);

  // Step 3: New card attributes
  newPlayer = signal('');
  newCardNumber = signal('');
  newParallelType = signal('Base');
  newIsRookie = signal(false);
  newIsAuto = signal(false);
  newIsPatch = signal(false);
  newIsSSP = signal(false);
  newSerialMax = signal<number | null>(null);

  // Step 4: User instance details
  pricePaid = signal<number | null>(null);
  serialNumber = signal('');
  isGraded = signal(false);
  grader = signal('PSA');
  gradeValue = signal('');

  private setSearchTimer: ReturnType<typeof setTimeout> | null = null;
  private cardSearchTimer: ReturnType<typeof setTimeout> | null = null;

  open() {
    this.reset();
    this.ui.addCardOpen.set(true);
  }

  close() {
    this.ui.addCardOpen.set(false);
  }

  private reset() {
    this.saveError.set(null);
    this.setQuery.set('');
    this.setResults.set([]);
    this.showSetDropdown.set(false);
    this.selectedSet.set(null);
    this.cardQuery.set('');
    this.cardResults.set([]);
    this.showCardDropdown.set(false);
    this.selectedMasterCard.set(null);
    this.isNewCard.set(false);
    this.noCardResults.set(false);
    this.newPlayer.set('');
    this.newCardNumber.set('');
    this.newParallelType.set('Base');
    this.newIsRookie.set(false);
    this.newIsAuto.set(false);
    this.newIsPatch.set(false);
    this.newIsSSP.set(false);
    this.newSerialMax.set(null);
    this.setParallels.set([]);
    this.parallelIsOther.set(false);
    this.pricePaid.set(null);
    this.serialNumber.set('');
    this.isGraded.set(false);
    this.grader.set('PSA');
    this.gradeValue.set('');
  }

  // ── Set Search ─────────────────────────────────────────

  onSetQueryChange(value: string) {
    this.setQuery.set(value);
    this.selectedSet.set(null);
    if (this.setSearchTimer) clearTimeout(this.setSearchTimer);
    if (!value.trim()) { this.setResults.set([]); this.showSetDropdown.set(false); return; }
    this.setSearchTimer = setTimeout(() => this.doSetSearch(value), 250);
  }

  private async doSetSearch(query: string) {
    const results = await this.setsService.searchSets(query);
    this.setResults.set(results);
    this.showSetDropdown.set(results.length > 0);
  }

  async selectSet(set: SetRecord) {
    this.selectedSet.set(set);
    this.setQuery.set(`${set.year} ${set.name}`);
    this.showSetDropdown.set(false);
    // Reset card + parallel selection when set changes
    this.cardQuery.set('');
    this.cardResults.set([]);
    this.selectedMasterCard.set(null);
    this.isNewCard.set(false);
    this.noCardResults.set(false);
    this.newParallelType.set('Base');
    this.parallelIsOther.set(false);
    // Load this set's defined parallels
    const parallels = await this.setsService.getParallels(set.id);
    this.setParallels.set(parallels);
  }

  clearSet() {
    this.selectedSet.set(null);
    this.setQuery.set('');
    this.cardQuery.set('');
    this.selectedMasterCard.set(null);
    this.isNewCard.set(false);
    this.setParallels.set([]);
    this.parallelIsOther.set(false);
  }

  // ── Card Search ────────────────────────────────────────

  onCardQueryChange(value: string) {
    this.cardQuery.set(value);
    this.selectedMasterCard.set(null);
    this.isNewCard.set(false);
    this.noCardResults.set(false);
    if (this.cardSearchTimer) clearTimeout(this.cardSearchTimer);
    if (!value.trim()) { this.cardResults.set([]); this.showCardDropdown.set(false); return; }
    this.cardSearchTimer = setTimeout(() => this.doCardSearch(value), 300);
  }

  private async doCardSearch(query: string) {
    const set = this.selectedSet();
    if (!set) return;
    const results = await this.cardsService.searchMasterCards(set.id, query);
    this.cardResults.set(results);
    this.showCardDropdown.set(true);
    this.noCardResults.set(results.length === 0);
  }

  selectMasterCard(card: MasterCard) {
    this.selectedMasterCard.set(card);
    this.isNewCard.set(false);
    this.showCardDropdown.set(false);
    this.cardQuery.set(this.cardLabel(card));
  }

  startNewCard() {
    this.isNewCard.set(true);
    this.selectedMasterCard.set(null);
    this.showCardDropdown.set(false);
    // Pre-fill player from the search query if it looks like a name
    const q = this.cardQuery().trim();
    if (q && !q.match(/^\d+$/)) this.newPlayer.set(q);
  }

  clearCardSelection() {
    this.selectedMasterCard.set(null);
    this.isNewCard.set(false);
    this.cardQuery.set('');
    this.cardResults.set([]);
    this.noCardResults.set(false);
  }

  cardLabel(card: MasterCard): string {
    const parts = [card.player];
    if (card.card_number) parts.push(`#${card.card_number}`);
    if (card.parallel_type && card.parallel_type !== 'Base') parts.push(card.parallel_type);
    return parts.join(' · ');
  }

  get canShowCardSearch(): boolean {
    return this.selectedSet() !== null;
  }

  get cardIsSelected(): boolean {
    return this.selectedMasterCard() !== null || this.isNewCard();
  }

  get canSave(): boolean {
    if (!this.selectedSet()) return false;
    if (!this.cardIsSelected) return false;
    if (this.isNewCard() && !this.newPlayer().trim()) return false;
    if (this.pricePaid() === null || this.pricePaid()! <= 0) return false;
    if (this.isGraded() && !this.gradeValue().trim()) return false;
    return true;
  }

  // ── Parallel Selection ─────────────────────────────────

  onParallelChange(value: string) {
    if (value === '__other__') {
      this.parallelIsOther.set(true);
      this.newParallelType.set('');
      this.newSerialMax.set(null);
      this.newIsAuto.set(false);
      return;
    }
    this.parallelIsOther.set(false);
    this.newParallelType.set(value);
    // Auto-fill serial_max and is_auto from the set parallel metadata
    const match = this.setParallels().find(p => p.name === value);
    if (match) {
      this.newSerialMax.set(match.serial_max);
      this.newIsAuto.set(match.is_auto);
    }
  }

  // ── Save ───────────────────────────────────────────────

  async save() {
    if (!this.canSave || this.saving()) return;
    this.saving.set(true);
    this.saveError.set(null);

    const { error } = await this.cardsService.addCardWithLookup({
      setId: this.selectedSet()!.id,
      masterCardId: this.selectedMasterCard()?.id ?? null,
      player: this.newPlayer(),
      cardNumber: this.newCardNumber(),
      parallelType: this.newParallelType(),
      isRookie: this.newIsRookie(),
      isAuto: this.newIsAuto(),
      isPatch: this.newIsPatch(),
      isSSP: this.newIsSSP(),
      serialMax: this.newSerialMax(),
      pricePaid: this.pricePaid(),
      serialNumber: this.serialNumber(),
      isGraded: this.isGraded(),
      grader: this.grader(),
      gradeValue: this.gradeValue(),
    });

    this.saving.set(false);

    if (error) {
      this.saveError.set(error.message ?? 'Failed to add card. Please try again.');
    } else {
      // Silently queue the custom parallel name for admin review
      if (this.parallelIsOther() && this.newParallelType().trim() && this.selectedSet()) {
        this.setsService.submitPendingParallel(this.selectedSet()!.id, this.newParallelType().trim());
      }
      this.cardAdded.emit();
      this.close();
    }
  }

  sportIcon(sport: string): string {
    const map: Record<string, string> = {
      Basketball: '🏀', Baseball: '⚾', Football: '🏈', Soccer: '⚽', Hockey: '🏒',
    };
    return map[sport] ?? '🃏';
  }
}
