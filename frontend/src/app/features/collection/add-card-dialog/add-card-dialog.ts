import { Component, inject, signal, computed, effect, untracked, Output, EventEmitter } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { CardsService, MasterCard } from '../../../core/services/cards';
import { ReleasesService, ReleaseRecord, SetParallel, SetRecord } from '../../../core/services/releases';
import { UiService } from '../../../core/services/ui';

const GRADERS = ['PSA', 'BGS', 'SGC', 'CGC', 'CSG'];

@Component({
  selector: 'app-add-card-dialog',
  imports: [CommonModule, FormsModule],
  templateUrl: './add-card-dialog.html',
  styleUrl: './add-card-dialog.scss',
})
export class AddCardDialog {
  private cardsService = inject(CardsService);
  private releasesService = inject(ReleasesService);
  private ui = inject(UiService);

  @Output() cardAdded = new EventEmitter<void>();

  readonly graders = GRADERS;

  readonly visible = this.ui.addCardOpen;
  saving = signal(false);
  saveError = signal<string | null>(null);

  // ── Step 1: Release ──────────────────────────────────────
  setQuery = signal('');
  setResults = signal<ReleaseRecord[]>([]);
  showSetDropdown = signal(false);
  selectedSet = signal<ReleaseRecord | null>(null);

  // ── Step 1.5: Set (subset within the release) ─────────────
  checklists = signal<SetRecord[]>([]);
  selectedChecklist = signal<SetRecord | null>(null);

  // ── Step 2: Card search ──────────────────────────────────
  cardQuery = signal('');
  cardResults = signal<MasterCard[]>([]);
  showCardDropdown = signal(false);
  selectedMasterCard = signal<MasterCard | null>(null);
  isNewCard = signal(false);
  noCardResults = signal(false);

  // ── Step 3: New card attributes ──────────────────────────
  newPlayer = signal('');
  newCardNumber = signal('');
  newSerialMax = signal<number | null>(null);
  newIsRookie = signal(false);
  newIsAuto = signal(false);
  newIsPatch = signal(false);
  newIsSSP = signal(false);

  // ── Parallel (instance-level, applies to all cards) ──────
  setParallels = signal<SetParallel[]>([]);
  selectedParallelId = signal<string | null>(null);
  selectedParallelName = signal('Base');
  parallelIsOther = signal(false);

  readonly selectedParallelSerialMax = computed(() => {
    const id = this.selectedParallelId();
    if (!id) return null;
    return this.setParallels().find(p => p.id === id)?.serial_max ?? null;
  });

  // ── Step 4: User instance ────────────────────────────────
  pricePaid = signal<number | null>(null);
  serialNumber = signal('');
  isGraded = signal(false);
  grader = signal('PSA');
  gradeValue = signal('');

  private setSearchTimer: ReturnType<typeof setTimeout> | null = null;
  private cardSearchTimer: ReturnType<typeof setTimeout> | null = null;

  constructor() {
    effect(() => {
      if (this.ui.addCardOpen()) {
        this.reset();
        untracked(() => this.applyPrefill());
      }
    });
  }

  private applyPrefill() {
    const prefill = this.ui.addCardPrefill();
    if (!prefill) return;
    this.ui.addCardPrefill.set(null);  // consume immediately

    // Set all signals directly — no async fetch needed because the scanner
    // already loaded this data and passed it in the prefill object.
    if (prefill.set) {
      this.selectedSet.set(prefill.set);
      this.setQuery.set(`${prefill.set.year} ${prefill.set.name}`);
    }
    if (prefill.checklists?.length) {
      this.checklists.set(prefill.checklists);
    }
    if (prefill.checklist) {
      this.selectedChecklist.set(prefill.checklist);
    }
    if (prefill.parallels?.length) {
      this.setParallels.set(prefill.parallels);
    }
    if (prefill.player) {
      this.newPlayer.set(prefill.player);
    }
    if (prefill.cardNumber) {
      this.newCardNumber.set(prefill.cardNumber);
    }
    if (prefill.player || prefill.cardNumber) {
      this.isNewCard.set(true);
    }
  }

  open() { this.reset(); this.ui.addCardOpen.set(true); }
  close() { this.ui.addCardOpen.set(false); }

  private reset() {
    this.saveError.set(null);
    this.setQuery.set('');
    this.setResults.set([]);
    this.showSetDropdown.set(false);
    this.selectedSet.set(null);
    this.checklists.set([]);
    this.selectedChecklist.set(null);
    this.cardQuery.set('');
    this.cardResults.set([]);
    this.showCardDropdown.set(false);
    this.selectedMasterCard.set(null);
    this.isNewCard.set(false);
    this.noCardResults.set(false);
    this.newPlayer.set('');
    this.newCardNumber.set('');
    this.newSerialMax.set(null);
    this.newIsRookie.set(false);
    this.newIsAuto.set(false);
    this.newIsPatch.set(false);
    this.newIsSSP.set(false);
    this.setParallels.set([]);
    this.selectedParallelId.set(null);
    this.selectedParallelName.set('Base');
    this.parallelIsOther.set(false);
    this.pricePaid.set(null);
    this.serialNumber.set('');
    this.isGraded.set(false);
    this.grader.set('PSA');
    this.gradeValue.set('');
  }

  // ── Set Search ───────────────────────────────────────────

  onSetQueryChange(value: string) {
    this.setQuery.set(value);
    this.selectedSet.set(null);
    this.selectedChecklist.set(null);
    this.checklists.set([]);
    if (this.setSearchTimer) clearTimeout(this.setSearchTimer);
    if (!value.trim()) { this.setResults.set([]); this.showSetDropdown.set(false); return; }
    this.setSearchTimer = setTimeout(() => this.doSetSearch(value), 250);
  }

  private async doSetSearch(query: string) {
    const results = await this.releasesService.searchReleases(query);
    this.setResults.set(results);
    this.showSetDropdown.set(results.length > 0);
  }

  async selectSet(release: ReleaseRecord) {
    this.selectedSet.set(release);
    this.setQuery.set(`${release.year} ${release.name}`);
    this.showSetDropdown.set(false);
    this.resetCardSection();
    this.setParallels.set([]);

    const sets = await this.releasesService.getSets(release.id);
    this.checklists.set(sets);
  }

  async selectChecklist(set: SetRecord) {
    this.selectedChecklist.set(set);
    this.resetCardSection();
    const parallels = await this.releasesService.getParallels(set.id);
    this.setParallels.set(parallels);
  }

  clearChecklist() {
    this.selectedChecklist.set(null);
    this.setParallels.set([]);
    this.resetCardSection();
  }

  clearSet() {
    this.selectedSet.set(null);
    this.setQuery.set('');
    this.checklists.set([]);
    this.selectedChecklist.set(null);
    this.setParallels.set([]);
    this.resetCardSection();
  }

  private resetCardSection() {
    this.cardQuery.set('');
    this.cardResults.set([]);
    this.selectedMasterCard.set(null);
    this.isNewCard.set(false);
    this.noCardResults.set(false);
    this.selectedParallelId.set(null);
    this.selectedParallelName.set('Base');
    this.parallelIsOther.set(false);
  }

  // ── Card Search ──────────────────────────────────────────

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
    const results = await this.cardsService.searchMasterCards(
      this.selectedChecklist()?.id ?? null,
      query
    );
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
    return parts.join(' · ');
  }

  get canShowCardSearch(): boolean {
    if (!this.selectedSet()) return false;
    // If this set has checklists, require one to be chosen.
    // If none exist yet (legacy sets pre-dating the checklist migration), allow proceeding.
    if (this.checklists().length > 0) return this.selectedChecklist() !== null;
    return true;
  }

  get cardIsSelected(): boolean {
    return this.selectedMasterCard() !== null || this.isNewCard();
  }

  get canSave(): boolean {
    if (!this.selectedChecklist()) return false;
    if (!this.cardIsSelected) return false;
    if (this.isNewCard() && !this.newPlayer().trim()) return false;
    if (this.pricePaid() === null || this.pricePaid()! <= 0) return false;
    if (this.isGraded() && !this.gradeValue().trim()) return false;
    return true;
  }

  // ── Parallel Selection ───────────────────────────────────

  onParallelChange(value: string) {
    if (value === '__other__') {
      this.parallelIsOther.set(true);
      this.selectedParallelId.set(null);
      this.selectedParallelName.set('');
      return;
    }
    this.parallelIsOther.set(false);
    // value is either parallel UUID (from set_parallels) or fallback name string
    const match = this.setParallels().find(p => p.id === value);
    if (match) {
      this.selectedParallelId.set(match.id);
      this.selectedParallelName.set(match.name + (match.serial_max ? ` /${match.serial_max}` : ''));
    } else {
      // fallback list — no FK, just a display name
      this.selectedParallelId.set(null);
      this.selectedParallelName.set(value === 'Base' ? 'Base' : value);
    }
  }

  // ── Save ─────────────────────────────────────────────────

  async save() {
    if (!this.canSave || this.saving()) return;
    this.saving.set(true);
    this.saveError.set(null);

    const { error, cardId } = await this.cardsService.addCardWithLookup({
      setId: this.selectedChecklist()?.id ?? null,
      masterCardId: this.selectedMasterCard()?.id ?? null,
      player: this.newPlayer(),
      cardNumber: this.newCardNumber(),
      serialMax: this.newSerialMax(),
      parallelId: this.selectedParallelId(),
      parallelName: this.selectedParallelName(),
      pendingParallelName: this.parallelIsOther() ? this.selectedParallelName().trim() : '',
      isRookie: this.newIsRookie(),
      isAuto: this.newIsAuto(),
      isPatch: this.newIsPatch(),
      isSSP: this.newIsSSP(),
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
      if (this.parallelIsOther() && this.selectedParallelName().trim() && this.selectedSet()) {
        this.releasesService.submitPendingParallel(this.selectedSet()!.id, this.selectedParallelName().trim());
      }
      // if (cardId) this.cardsService.fetchMarketValue(cardId);
      // Lazily fetch card image if this was a catalog card without one yet
      const mc = this.selectedMasterCard();
      if (mc?.id && !mc.image_url) this.cardsService.fetchCardImage(mc.id);
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
