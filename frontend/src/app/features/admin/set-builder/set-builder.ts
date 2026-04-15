import { Component, inject, signal, computed, OnInit } from '@angular/core';
import { ReactiveFormsModule, FormBuilder, Validators } from '@angular/forms';
import { CommonModule, DecimalPipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { MessageService } from 'primeng/api';
import { Toast } from 'primeng/toast';
import { ReleasesService, ReleaseRecord, UpsertParallelPayload } from '../../../core/services/releases';
import { CardsightService, CardsightReleaseResult } from '../../../core/services/cardsight';

const RELEASES_PAGE_SIZE = 10;

@Component({
  selector: 'app-release-builder',
  imports: [CommonModule, DecimalPipe, ReactiveFormsModule, FormsModule, RouterLink, Toast],
  providers: [MessageService],
  templateUrl: './set-builder.html',
  styleUrl: './set-builder.scss',
})
export class ReleaseBuilder implements OnInit {
  private fb = inject(FormBuilder);
  private releasesService = inject(ReleasesService);
  private cardsightService = inject(CardsightService);
  private messageService = inject(MessageService);

  readonly sports = ['Basketball', 'Baseball', 'Football', 'Soccer'];
  readonly releaseTypes = ['Hobby', 'Retail', 'FOTL'];

  showManualForm = signal(false);

  releases = signal<ReleaseRecord[]>([]);
  releasesSearch = signal('');
  releasesPage = signal(0);

  filteredReleases = computed(() => {
    const q = this.releasesSearch().toLowerCase().trim();
    return q
      ? this.releases().filter(r =>
          r.name.toLowerCase().includes(q) ||
          String(r.year).includes(q) ||
          r.sport.toLowerCase().includes(q)
        )
      : this.releases();
  });

  pagedReleases = computed(() =>
    this.filteredReleases().slice(
      this.releasesPage() * RELEASES_PAGE_SIZE,
      (this.releasesPage() + 1) * RELEASES_PAGE_SIZE
    )
  );

  totalPages = computed(() =>
    Math.max(1, Math.ceil(this.filteredReleases().length / RELEASES_PAGE_SIZE))
  );

  saving = signal(false);
  duplicateError = signal(false);

  // CardSight search state
  csYear: number = new Date().getFullYear();
  csManufacturer = '';
  csSegment = '';
  csResults = signal<CardsightReleaseResult[]>([]);
  csSearching = signal(false);
  csImportingId = signal<string | null>(null);
  csImportProgress = signal(0);
  csSearched = signal(false);

  // CardSight results filter + pagination
  csFilter = signal('');
  csPage = signal(0);

  csFilteredResults = computed(() => {
    const q = this.csFilter().toLowerCase().trim();
    return q
      ? this.csResults().filter(r => r.name.toLowerCase().includes(q) || String(r.year).includes(q))
      : this.csResults();
  });

  csPagedResults = computed(() =>
    this.csFilteredResults().slice(
      this.csPage() * RELEASES_PAGE_SIZE,
      (this.csPage() + 1) * RELEASES_PAGE_SIZE
    )
  );

  csTotalPages = computed(() =>
    Math.max(1, Math.ceil(this.csFilteredResults().length / RELEASES_PAGE_SIZE))
  );

  importedCardsightIds = computed(() =>
    new Set(this.releases().map(r => r.cardsight_id).filter(Boolean))
  );

  // Per-result expanded options state
  csExpandedId = signal<string | null>(null);
  csOptionsByResult: Record<string, { releaseType: string }> = {};

  private progressTimer: ReturnType<typeof setInterval> | undefined = undefined;

  bulkParallels = '';
  bulkSets = '';

  form = this.fb.group({
    name: ['', Validators.required],
    year: [new Date().getFullYear(), [Validators.required, Validators.min(1901)]],
    sport: ['Basketball', Validators.required],
    release_type: ['Hobby', Validators.required],
  });

  ngOnInit() {
    this.loadReleases();
  }

  private async loadReleases() {
    const data = await this.releasesService.getReleases();
    this.releases.set(data);
  }

  generateSlug(): string {
    const { year, name, sport, release_type } = this.form.value;
    return [year, name, sport, release_type]
      .map(v => String(v ?? '').toLowerCase().trim().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, ''))
      .join('-');
  }

  async submit() {
    if (this.form.invalid) {
      this.form.markAllAsTouched();
      return;
    }

    this.saving.set(true);
    this.duplicateError.set(false);

    const { name, year, sport } = this.form.value;
    const isDupe = await this.releasesService.checkDuplicate(name!, year!, sport!);
    if (isDupe) {
      this.duplicateError.set(true);
      this.saving.set(false);
      return;
    }

    const payload = {
      name: name!,
      year: year!,
      sport: sport!,
      release_type: this.form.value.release_type!,
      set_slug: this.generateSlug(),
      cardsight_id: null,
      source: 'manual',
    };

    const { data: newRelease, error } = await this.releasesService.createRelease(payload);
    this.saving.set(false);

    if (error) {
      this.messageService.add({ severity: 'error', summary: 'Error', detail: error.message });
    } else {
      const releaseId = newRelease!.id;

      // Always create the Base Set — capture its ID for parallels
      const { data: baseSet } = await this.releasesService.createSet(releaseId, 'Base Set', null);

      // Create any additional insert sets
      const extraSets = this.parseSets(releaseId);
      for (const s of extraSets) {
        await this.releasesService.createSet(s.releaseId, s.name, s.prefix);
      }

      // Save parallels (belong to the Base Set)
      let parallelCount = 0;
      if (baseSet) {
        const parallels = this.parseParallels(baseSet.id);
        parallelCount = parallels.length;
        if (parallels.length > 0) {
          await this.releasesService.upsertParallels(parallels);
        }
      }

      const setNote = extraSets.length > 0 ? ` + ${extraSets.length + 1} sets` : '';
      const parallelNote = parallelCount > 0 ? `, ${parallelCount} parallels` : '';
      this.messageService.add({ severity: 'success', summary: 'Release Created', detail: `"${name}" added${setNote}${parallelNote}.` });
      this.showManualForm.set(false);
      this.form.reset({
        name: '',
        year: new Date().getFullYear(),
        sport: 'Basketball',
        release_type: 'Hobby',
      });
      this.bulkParallels = '';
      this.bulkSets = '';
      await this.loadReleases();
    }
  }

  private parseSets(releaseId: string): { releaseId: string; name: string; prefix: string | null }[] {
    if (!this.bulkSets.trim()) return [];
    return this.bulkSets
      .split(',')
      .map(s => s.trim())
      .filter(s => s.length > 0)
      .map(raw => {
        const [name, prefix] = raw.split(':').map(p => p.trim());
        return { releaseId, name, prefix: prefix || null };
      });
  }

  private parseParallels(setId: string): UpsertParallelPayload[] {
    if (!this.bulkParallels.trim()) return [];
    return this.bulkParallels
      .split(',')
      .map(s => s.trim())
      .filter(s => s.length > 0)
      .map((raw, i) => {
        const parts = raw.split(':').map(p => p.trim());
        const serial_max = parts[1] ? parseInt(parts[1], 10) : null;
        return {
          set_id: setId,
          name: parts[0],
          serial_max: serial_max !== null && !isNaN(serial_max) ? serial_max : null,
          is_auto: parts[2]?.toLowerCase() === 'auto',
          color_hex: null,
          sort_order: i,
        };
      });
  }

  onCsFilter(q: string) {
    this.csFilter.set(q);
    this.csPage.set(0);
  }

  async searchCardSight() {
    this.csSearching.set(true);
    this.csSearched.set(false);
    this.csResults.set([]);
    this.csFilter.set('');
    this.csPage.set(0);
    try {
      const results = await this.cardsightService.searchReleases({
        year:         this.csYear       || undefined,
        manufacturer: this.csManufacturer.trim() || undefined,
        segment:      this.csSegment    || undefined,
      });
      this.csResults.set(results);
      this.csSearched.set(true);
    } catch (e: any) {
      console.error('[searchCardSight]', e);
      this.messageService.add({ severity: 'error', summary: 'Search Failed', detail: e?.message ?? 'Unknown error' });
    } finally {
      this.csSearching.set(false);
    }
  }

  expandImportOptions(result: CardsightReleaseResult) {
    if (!this.csOptionsByResult[result.id]) {
      this.csOptionsByResult[result.id] = { releaseType: 'Hobby' };
    }
    this.csExpandedId.set(result.id);
  }

  collapseImportOptions() {
    this.csExpandedId.set(null);
  }

  async importFromCardSight(result: CardsightReleaseResult) {
    const opts = this.csOptionsByResult[result.id] ?? { releaseType: 'Hobby' };
    this.csExpandedId.set(null);
    this.csImportingId.set(result.id);
    this.csImportProgress.set(0);

    // Advance progress toward 90% over ~20s; jump to 100% on completion
    const TICK_MS = 200;
    const TARGET = 90;
    const DURATION_MS = 20_000;
    const step = (TARGET / (DURATION_MS / TICK_MS));
    this.progressTimer = setInterval(() => {
      const next = Math.min(this.csImportProgress() + step, TARGET);
      this.csImportProgress.set(next);
    }, TICK_MS);

    try {
      const sport = this.csSegment || null;
      const imported = await this.cardsightService.importRelease(result.id, sport, opts.releaseType);
      clearInterval(this.progressTimer);
      this.progressTimer = undefined;
      this.csImportProgress.set(100);
      await new Promise(r => setTimeout(r, 600)); // brief flash of 100%
      this.messageService.add({
        severity: 'success',
        summary: 'Imported',
        detail: `"${imported.releaseName}" — ${imported.setsCount} sets, ${imported.parallelsCount} parallels.`,
      });
      await this.loadReleases();
    } catch (e: any) {
      clearInterval(this.progressTimer);
      this.progressTimer = undefined;
      this.messageService.add({ severity: 'error', summary: 'Import Failed', detail: e.message });
    } finally {
      this.csImportingId.set(null);
      this.csImportProgress.set(0);
    }
  }

  onReleasesSearch(q: string) {
    this.releasesSearch.set(q);
    this.releasesPage.set(0);
  }

  setReleaseType(rt: string) {
    this.form.get('release_type')?.setValue(rt);
  }

  sportIcon(sport: string): string {
    const map: Record<string, string> = {
      Basketball: '🏀', Baseball: '⚾', Football: '🏈', Soccer: '⚽',
    };
    return map[sport] ?? '🃏';
  }
}
