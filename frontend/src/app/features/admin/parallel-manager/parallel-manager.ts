import { Component, inject, signal, OnInit, computed } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { MessageService } from 'primeng/api';
import { Toast } from 'primeng/toast';
import { SetsService, SetRecord, SetParallel, ChecklistRecord } from '../../../core/services/sets';

interface ParsedParallel {
  name: string;
  serial_max: number | null;
  is_auto: boolean;
  color_hex: string | null;
  sort_order: number;
  /** true = already saved in DB */
  saved: boolean;
  id?: string;
}

@Component({
  selector: 'app-parallel-manager',
  imports: [CommonModule, FormsModule, RouterLink, Toast],
  providers: [MessageService],
  templateUrl: './parallel-manager.html',
  styleUrl: './parallel-manager.scss',
})
export class ParallelManager implements OnInit {
  private route = inject(ActivatedRoute);
  private setsService = inject(SetsService);
  private messageService = inject(MessageService);

  set = signal<SetRecord | null>(null);
  checklist = signal<ChecklistRecord | null>(null);
  parallels = signal<SetParallel[]>([]);
  saving = signal(false);
  deleting = signal<string | null>(null);

  bulkInput = '';
  parseError = signal('');
  parsed = signal<ParsedParallel[]>([]);

  readonly setId       = this.route.snapshot.paramMap.get('setId')!;
  readonly checklistId = this.route.snapshot.paramMap.get('checklistId')!;

  parallelCount = computed(() => this.parallels().length);

  ngOnInit() {
    this.loadSet();
    this.loadChecklist();
    this.loadParallels();
  }

  private async loadSet() {
    const sets = await this.setsService.getSets();
    this.set.set(sets.find(s => s.id === this.setId) ?? null);
  }

  private async loadChecklist() {
    const checklists = await this.setsService.getChecklists(this.setId);
    this.checklist.set(checklists.find(c => c.id === this.checklistId) ?? null);
  }

  private async loadParallels() {
    const data = await this.setsService.getParallels(this.checklistId);
    this.parallels.set(data);
  }

  parseBulkInput() {
    this.parseError.set('');
    if (!this.bulkInput.trim()) {
      this.parseError.set('Paste at least one parallel name.');
      return;
    }

    const items = this.bulkInput
      .split(',')
      .map(s => s.trim())
      .filter(s => s.length > 0);

    if (items.length === 0) {
      this.parseError.set('No valid entries found.');
      return;
    }

    const result: ParsedParallel[] = items.map((raw, i) => {
      // Format: "Name:serialMax" or "Name:serialMax:auto" or just "Name"
      const parts = raw.split(':').map(p => p.trim());
      const name = parts[0];
      const serial_max = parts[1] ? parseInt(parts[1], 10) : null;
      const is_auto = parts[2]?.toLowerCase() === 'auto';

      return {
        name,
        serial_max: serial_max !== null && !isNaN(serial_max) ? serial_max : null,
        is_auto,
        color_hex: null,
        sort_order: i,
        saved: false,
      };
    });

    this.parsed.set(result);
  }

  clearParsed() {
    this.parsed.set([]);
    this.bulkInput = '';
    this.parseError.set('');
  }

  async saveParallels() {
    const items = this.parsed();
    if (items.length === 0) return;

    this.saving.set(true);
    const payload = items.map((p, i) => ({
      checklist_id: this.checklistId,
      name: p.name,
      serial_max: p.serial_max,
      is_auto: p.is_auto,
      color_hex: p.color_hex,
      sort_order: i,
    }));

    const { error } = await this.setsService.upsertParallels(payload);
    this.saving.set(false);

    if (error) {
      this.messageService.add({ severity: 'error', summary: 'Error', detail: (error as any).message });
    } else {
      this.messageService.add({ severity: 'success', summary: 'Saved', detail: `${items.length} parallel(s) saved.` });
      this.clearParsed();
      await this.loadParallels();
    }
  }

  async deleteParallel(p: SetParallel) {
    this.deleting.set(p.id);
    await this.setsService.deleteParallel(p.id);
    this.deleting.set(null);
    await this.loadParallels();
  }

  serialLabel(p: SetParallel | ParsedParallel): string {
    if (p.serial_max === 1) return '1/1';
    if (p.serial_max) return `/${p.serial_max}`;
    return '';
  }

  sportIcon(sport: string): string {
    const map: Record<string, string> = {
      Basketball: '🏀', Baseball: '⚾', Football: '🏈', Soccer: '⚽',
    };
    return map[sport] ?? '🃏';
  }
}
