import { Component, inject, signal, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import Papa from 'papaparse';
import { ReleasesService, ReleaseRecord, SetRecord } from '../../../core/services/releases';
import { AuthService } from '../../../core/services/auth';
import { environment } from '../../../../environments/environment';

const SCHEMA_FIELDS = [
  { key: 'player',       label: 'Player Name',    required: true  },
  { key: 'cardNumber',   label: 'Card #',          required: false },
  { key: 'year',         label: 'Year',            required: false },
  { key: 'setName',      label: 'Release Name',    required: false },
  { key: 'sport',        label: 'Sport',           required: false },
  { key: 'subsetName',   label: 'Set / Subset',    required: false },
  { key: 'parallel',     label: 'Parallel',        required: false },
  { key: 'pricePaid',    label: 'Price Paid',      required: false },
  { key: 'serialNumber', label: 'Serial # (e.g. 34/99)', required: false },
  { key: 'serialMax',    label: 'Print Run (/N)',  required: false },
  { key: 'isRookie',     label: 'Rookie (RC)',     required: false },
  { key: 'isAuto',       label: 'Autograph',       required: false },
  { key: 'isPatch',      label: 'Patch / Mem',     required: false },
  { key: 'isGraded',     label: 'Graded',          required: false },
  { key: 'grader',       label: 'Grader',          required: false },
  { key: 'gradeValue',   label: 'Grade',           required: false },
] as const;

type SchemaKey = typeof SCHEMA_FIELDS[number]['key'];

type ReleaseStatus = 'matched' | 'fuzzy' | 'new';

const SEARCH_PAGE_SIZE = 10;

interface ResolvedRelease {
  tempId: string;
  releaseName: string;
  releaseYear: number;
  sport: string;
  subsetName: string;
  rowCount: number;
  status: ReleaseStatus;
  existingReleaseId: string | undefined;
  existingSetId: string | undefined;
  releaseType: string;
  availableSets: SetRecord[];
  searchQuery: string;
  searchResults: ReleaseRecord[];
  searchPage: number;
  searchHasMore: boolean;
  searchLoading: boolean;
  showSearch: boolean;
}

interface ParsedCard {
  rowIndex: number;
  releaseTempId: string;
  player: string;
  cardNumber: string | undefined;
  isRookie: boolean;
  isAuto: boolean;
  isPatch: boolean;
  serialMax: number | undefined;
  parallelName: string;
  pricePaid: number;
  serialNumber: string | undefined;
  isGraded: boolean;
  grader: string | undefined;
  gradeValue: string | undefined;
  errors: string[];
}

const AUTO_MAP_PATTERNS: Record<SchemaKey, string[]> = {
  player:       ['player name', 'player', 'athlete', 'name'],
  cardNumber:   ['card #', 'card#', 'card number', 'card no.', 'card no', 'no.', 'num', '#', 'number', 'no'],
  year:         ['year', 'release year', 'yr'],
  setName:      ['release name', 'release', 'product name', 'product', 'brand', 'set name', 'card set', 'collection', 'set'],
  sport:        ['sport', 'league'],
  subsetName:   ['subset name', 'subset', 'sub-set', 'sub set', 'insert name', 'insert', 'checklist', 'variation'],
  parallel:     ['parallel name', 'parallel', 'color', 'refractor', 'finish'],
  pricePaid:    ['price paid', 'purchase price', 'cost', 'paid', 'price'],
  serialNumber: ['serial number', 'serial #', 'serial no', 'serial', 'copy', 'numbered'],
  serialMax:    ['print run', 'serial max', '/n', 'run', 'max'],
  isRookie:     ['rookie', 'rc', 'is rookie'],
  isAuto:       ['autograph', 'auto', 'is auto'],
  isPatch:      ['patch', 'memorabilia', 'mem', 'is patch'],
  isGraded:     ['graded', 'is graded', 'slabbed'],
  grader:       ['grading company', 'grader'],
  gradeValue:   ['grade value', 'grade', 'score'],
};

function parseBool(val: string | undefined): boolean {
  if (!val) return false;
  const v = val.toLowerCase().trim();
  return v === 'true' || v === 'yes' || v === '1' || v === 'y' || v === 'x';
}

@Component({
  selector: 'app-csv-import',
  imports: [CommonModule, FormsModule],
  templateUrl: './csv-import.html',
})
export class CsvImport {
  private releasesService = inject(ReleasesService);
  private auth = inject(AuthService);
  private router = inject(Router);

  readonly schemaFields = SCHEMA_FIELDS;
  readonly releaseTypes = ['Unknown', 'Hobby', 'Retail'];
  readonly sports = ['Basketball', 'Baseball', 'Football', 'Soccer', 'Hockey', 'Other'];

  // ── Step ─────────────────────────────────────────────────────────────────
  step = signal<1 | 2 | 3>(1);

  // ── Step 1 ────────────────────────────────────────────────────────────────
  csvHeaders  = signal<string[]>([]);
  rawRows     = signal<Record<string, string>[]>([]);
  mapping     = signal<Record<string, string>>({});
  uploadError = signal<string | null>(null);
  fileName    = signal<string | null>(null);

  canProceedToStep2 = computed(() =>
    !!this.mapping()['player'] && this.rawRows().length > 0
  );

  previewRows = computed(() => this.rawRows().slice(0, 3));

  // ── Step 2 ────────────────────────────────────────────────────────────────
  resolvedReleases  = signal<ResolvedRelease[]>([]);
  resolutionLoading = signal(false);
  parsedCards       = signal<ParsedCard[]>([]);

  canProceedToStep3 = computed(() =>
    this.resolvedReleases().length > 0 &&
    this.resolvedReleases().every(r => r.status !== 'fuzzy')
  );

  unresolvedCount = computed(() =>
    this.resolvedReleases().filter(r => r.status === 'fuzzy').length
  );

  groupedReleases = computed(() => ({
    matched: this.resolvedReleases().filter(r => r.status === 'matched'),
    fuzzy:   this.resolvedReleases().filter(r => r.status === 'fuzzy'),
    new:     this.resolvedReleases().filter(r => r.status === 'new'),
  }));

  openGroups = signal<Set<ReleaseStatus>>(new Set<ReleaseStatus>(['fuzzy', 'new']));

  // ── Step 3 ────────────────────────────────────────────────────────────────
  committing   = signal(false);
  commitError  = signal<string | null>(null);
  commitResult = signal<{ inserted: number; releasesCreated: number; setsCreated: number } | null>(null);
  showErrors   = signal(false);

  errorCount   = computed(() => this.parsedCards().filter(c => c.errors.length > 0).length);
  validCount   = computed(() => this.parsedCards().filter(c => c.errors.length === 0).length);
  newReleases  = computed(() => this.resolvedReleases().filter(r => !r.existingReleaseId).length);
  newSets      = computed(() => this.resolvedReleases().filter(r => !r.existingSetId).length);

  // ── File upload ───────────────────────────────────────────────────────────
  onFileChange(event: Event) {
    const file = (event.target as HTMLInputElement).files?.[0];
    if (!file) return;
    this.uploadError.set(null);
    this.fileName.set(file.name);
    this.rawRows.set([]);
    this.csvHeaders.set([]);

    Papa.parse(file, {
      header: true,
      skipEmptyLines: true,
      complete: (result) => {
        if (result.errors.length > 0 && result.data.length === 0) {
          this.uploadError.set('Could not parse CSV. Please check the file format.');
          return;
        }
        const headers = result.meta.fields ?? [];
        this.csvHeaders.set(headers);
        this.rawRows.set(result.data as Record<string, string>[]);
        this.autoMap(headers);
      },
      error: (err: any) => this.uploadError.set(`Parse error: ${err.message}`),
    });
  }

  private autoMap(headers: string[]) {
    const lower = headers.map(h => h.toLowerCase().trim());
    const mapped: Record<string, string> = {};
    const used = new Set<number>();

    for (const [key, candidates] of Object.entries(AUTO_MAP_PATTERNS)) {
      let found = -1;

      // Pass 1: exact match (prefer unclaimed columns)
      for (const candidate of candidates) {
        found = lower.findIndex((h, i) => !used.has(i) && h === candidate);
        if (found >= 0) break;
      }

      // Pass 2: header contains the candidate string (handles "Card # (Optional)" etc.)
      if (found < 0) {
        for (const candidate of candidates) {
          found = lower.findIndex((h, i) => !used.has(i) && h.includes(candidate));
          if (found >= 0) break;
        }
      }

      if (found >= 0) {
        mapped[key] = headers[found];
        used.add(found);
      }
    }

    this.mapping.set(mapped);
  }

  setMapping(schemaKey: string, csvColumn: string) {
    this.mapping.update(m => ({ ...m, [schemaKey]: csvColumn }));
  }

  getMapped(key: string): string {
    return this.mapping()[key] ?? '';
  }

  // ── Step 2: Parse + resolve ───────────────────────────────────────────────
  async proceedToStep2() {
    this.goToStep(2);
    this.resolutionLoading.set(true);
    const m = this.mapping();
    const rows = this.rawRows();

    const sigMap = new Map<string, ResolvedRelease & { rowCount: number }>();
    const cards: ParsedCard[] = [];

    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      const errors: string[] = [];

      const player = (m['player'] ? row[m['player']] : '').trim();
      if (!player) errors.push('Missing player name');

      const releaseName  = (m['setName']     ? row[m['setName']]     : '').trim() || 'Unknown Release';
      const yearRaw      = (m['year']         ? row[m['year']]         : '').trim();
      const releaseYear  = parseInt(yearRaw, 10) || new Date().getFullYear();
      const sport        = (m['sport']        ? row[m['sport']]        : '').trim() || 'Unknown';
      const subsetName   = (m['subsetName']   ? row[m['subsetName']]   : '').trim() || 'Base Set';

      const sigKey = `${releaseYear}|${releaseName.toLowerCase()}|${sport.toLowerCase()}|${subsetName.toLowerCase()}`;

      if (!sigMap.has(sigKey)) {
        sigMap.set(sigKey, {
          tempId: crypto.randomUUID(),
          releaseName, releaseYear, sport, subsetName,
          rowCount: 0,
          status: 'new',
          existingReleaseId: undefined,
          existingSetId: undefined,
          releaseType: 'Unknown',
          availableSets: [],
          searchQuery: `${releaseYear} ${releaseName}`,
          searchResults: [],
          searchPage: 0,
          searchHasMore: false,
          searchLoading: false,
          showSearch: false,
        });
      }
      const sig = sigMap.get(sigKey)!;
      sig.rowCount++;

      // Parse serial number: "34/99" → { serialNumber: "34", serialMax: 99 }
      const serialRaw = (m['serialNumber'] ? row[m['serialNumber']] : '').trim();
      let serialNumber: string | undefined;
      let serialMax: number | undefined;
      if (serialRaw) {
        const parts = serialRaw.split('/');
        if (parts.length === 2) {
          serialNumber = parts[0].trim() || undefined;
          serialMax = parseInt(parts[1].trim(), 10) || undefined;
        } else {
          serialNumber = serialRaw;
        }
      }
      if (!serialMax && m['serialMax']) {
        const sm = (row[m['serialMax']] ?? '').trim();
        if (sm) serialMax = parseInt(sm, 10) || undefined;
      }

      const pricePaidRaw = (m['pricePaid'] ? row[m['pricePaid']] : '').replace(/[$,]/g, '');
      const pricePaid = parseFloat(pricePaidRaw) || 0;

      cards.push({
        rowIndex: i,
        releaseTempId: sig.tempId,
        player,
        cardNumber: (m['cardNumber'] ? row[m['cardNumber']] : '')?.trim() || undefined,
        isRookie:  parseBool(m['isRookie']  ? row[m['isRookie']]  : ''),
        isAuto:    parseBool(m['isAuto']    ? row[m['isAuto']]    : ''),
        isPatch:   parseBool(m['isPatch']   ? row[m['isPatch']]   : ''),
        serialMax,
        parallelName: (m['parallel'] ? row[m['parallel']] : '').trim() || 'Base',
        pricePaid,
        serialNumber,
        isGraded:  parseBool(m['isGraded'] ? row[m['isGraded']] : ''),
        grader:    (m['grader']     ? row[m['grader']]     : '')?.trim() || undefined,
        gradeValue:(m['gradeValue'] ? row[m['gradeValue']] : '')?.trim() || undefined,
        errors,
      });
    }

    this.parsedCards.set(cards);

    // Fuzzy-match each unique release against DB
    const resolved: ResolvedRelease[] = [];
    for (const sig of sigMap.values()) {
      const results = await this.releasesService.searchReleases(`${sig.releaseYear} ${sig.releaseName}`, SEARCH_PAGE_SIZE);
      const exact = results.find(r =>
        r.year === sig.releaseYear &&
        r.name.toLowerCase().includes(sig.releaseName.toLowerCase().substring(0, 8))
      );

      let status: ReleaseStatus = 'new';
      let existingReleaseId: string | undefined;
      let existingSetId: string | undefined;
      let availableSets: SetRecord[] = [];

      if (exact) {
        const sets = await this.releasesService.getSets(exact.id);
        const matchedSet = sets.find(s => s.name.toLowerCase() === sig.subsetName.toLowerCase());
        status = matchedSet ? 'matched' : 'fuzzy';
        existingReleaseId = exact.id;
        existingSetId = matchedSet?.id;
        availableSets = sets;
      }

      resolved.push({
        ...sig,
        status,
        existingReleaseId,
        existingSetId,
        availableSets,
        searchResults: results,
        searchPage: 0,
        searchHasMore: results.length === SEARCH_PAGE_SIZE,
        searchLoading: false,
      });
    }

    const statusOrder: Record<ReleaseStatus, number> = { matched: 0, fuzzy: 1, new: 2 };
    resolved.sort((a, b) => statusOrder[a.status] - statusOrder[b.status]);

    this.resolvedReleases.set(resolved);
    this.resolutionLoading.set(false);
  }

  // ── Release resolution actions ────────────────────────────────────────────
  private searchTimers = new Map<number, ReturnType<typeof setTimeout>>();

  onSearchQueryChange(idx: number, query: string) {
    this.resolvedReleases.update(list => {
      const copy = [...list];
      copy[idx] = { ...copy[idx], searchQuery: query };
      return copy;
    });
    const existing = this.searchTimers.get(idx);
    if (existing) clearTimeout(existing);
    this.searchTimers.set(idx, setTimeout(() => this.searchForRelease(idx, query), 300));
  }

  async searchForRelease(idx: number, query: string) {
    this.resolvedReleases.update(list => {
      const copy = [...list];
      copy[idx] = { ...copy[idx], searchQuery: query, searchLoading: true, searchPage: 0 };
      return copy;
    });
    const results = await this.releasesService.searchReleases(query, SEARCH_PAGE_SIZE, 0);
    this.resolvedReleases.update(list => {
      const copy = [...list];
      copy[idx] = {
        ...copy[idx],
        searchResults: results,
        searchPage: 0,
        searchHasMore: results.length === SEARCH_PAGE_SIZE,
        searchLoading: false,
        showSearch: true,
      };
      return copy;
    });
  }

  async goToPage(idx: number, page: number) {
    const rel = this.resolvedReleases()[idx];
    this.resolvedReleases.update(list => {
      const copy = [...list]; copy[idx] = { ...copy[idx], searchLoading: true }; return copy;
    });
    const results = await this.releasesService.searchReleases(rel.searchQuery, SEARCH_PAGE_SIZE, page * SEARCH_PAGE_SIZE);
    this.resolvedReleases.update(list => {
      const copy = [...list];
      copy[idx] = {
        ...copy[idx],
        searchResults: results,
        searchPage: page,
        searchHasMore: results.length === SEARCH_PAGE_SIZE,
        searchLoading: false,
      };
      return copy;
    });
  }

  async linkToRelease(idx: number, release: ReleaseRecord) {
    const sets = await this.releasesService.getSets(release.id);
    this.resolvedReleases.update(list => {
      const copy = [...list];
      const sig = copy[idx];
      const matchedSet = sets.find(s => s.name.toLowerCase() === sig.subsetName.toLowerCase());
      copy[idx] = {
        ...sig,
        status: matchedSet ? 'matched' : 'fuzzy',
        existingReleaseId: release.id,
        existingSetId: matchedSet?.id,
        availableSets: sets,
        showSearch: false,
        searchQuery: `${release.year} ${release.name}`,
      };
      return copy;
    });
  }

  linkToSet(idx: number, setId: string) {
    this.resolvedReleases.update(list => {
      const copy = [...list];
      copy[idx] = { ...copy[idx], existingSetId: setId || undefined, status: 'matched' };
      return copy;
    });
  }

  createNewSetUnderRelease(idx: number) {
    // Keep existingReleaseId but clear existingSetId → backend creates the set
    this.resolvedReleases.update(list => {
      const copy = [...list];
      copy[idx] = { ...copy[idx], existingSetId: undefined, status: 'matched' };
      return copy;
    });
  }

  markAsNew(idx: number) {
    this.resolvedReleases.update(list => {
      const copy = [...list];
      copy[idx] = {
        ...copy[idx],
        status: 'new',
        existingReleaseId: undefined,
        existingSetId: undefined,
        showSearch: false,
      };
      return copy;
    });
  }

  updateReleaseType(idx: number, value: string) {
    this.resolvedReleases.update(list => {
      const copy = [...list]; copy[idx] = { ...copy[idx], releaseType: value }; return copy;
    });
  }

  updateSport(idx: number, value: string) {
    this.resolvedReleases.update(list => {
      const copy = [...list]; copy[idx] = { ...copy[idx], sport: value }; return copy;
    });
  }

  toggleGroup(status: ReleaseStatus) {
    this.openGroups.update(s => {
      const next = new Set(s);
      next.has(status) ? next.delete(status) : next.add(status);
      return next;
    });
  }

  releaseIndex(tempId: string): number {
    return this.resolvedReleases().findIndex(r => r.tempId === tempId);
  }

  toggleSearch(idx: number) {
    this.resolvedReleases.update(list => {
      const copy = [...list];
      copy[idx] = { ...copy[idx], showSearch: !copy[idx].showSearch };
      return copy;
    });
  }

  // ── Commit ────────────────────────────────────────────────────────────────
  async commit() {
    this.committing.set(true);
    this.commitError.set(null);

    const releases = this.resolvedReleases().map(r => ({
      tempId:            r.tempId,
      existingReleaseId: r.existingReleaseId,
      existingSetId:     r.existingSetId,
      releaseName:       r.releaseName,
      releaseYear:       r.releaseYear,
      sport:             r.sport,
      releaseType:       r.releaseType,
      setName:           r.subsetName,
    }));

    const cards = this.parsedCards()
      .filter(c => c.errors.length === 0)
      .map(c => ({
        releaseTempId:  c.releaseTempId,
        player:         c.player,
        cardNumber:     c.cardNumber,
        isRookie:       c.isRookie,
        isAuto:         c.isAuto,
        isPatch:        c.isPatch,
        serialMax:      c.serialMax,
        parallelName:   c.parallelName,
        pricePaid:      c.pricePaid,
        serialNumber:   c.serialNumber,
        isGraded:       c.isGraded,
        grader:         c.grader,
        gradeValue:     c.gradeValue,
      }));

    try {
      const session = await this.auth.getSession();
      if (!session) throw new Error('Not authenticated');

      const res = await fetch(`${environment.apiUrl}/api/import`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${session.access_token}`,
        },
        body: JSON.stringify({ releases, cards }),
      });

      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? 'Import failed');
      this.commitResult.set(data);
    } catch (e: any) {
      this.commitError.set(e.message);
    } finally {
      this.committing.set(false);
    }
  }

  goToStep(n: 1 | 2 | 3) {
    this.step.set(n);
    document.getElementById('app-content')?.scrollTo({ top: 0, behavior: 'instant' });
  }

  goBack() { this.router.navigate(['/collection']); }
  goToCollection() { this.router.navigate(['/collection']); }

  statusBadgeClass(status: ReleaseStatus): string {
    if (status === 'matched') return 'bg-emerald-100 text-emerald-700';
    if (status === 'fuzzy')   return 'bg-amber-100 text-amber-700';
    return 'bg-gray-100 text-gray-500';
  }

  statusLabel(status: ReleaseStatus): string {
    if (status === 'matched') return 'Matched';
    if (status === 'fuzzy')   return 'Needs Review';
    return 'New';
  }
}
