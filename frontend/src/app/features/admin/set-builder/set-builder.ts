import { Component, inject, signal, OnInit } from '@angular/core';
import { ReactiveFormsModule, FormBuilder, Validators } from '@angular/forms';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { MessageService } from 'primeng/api';
import { Toast } from 'primeng/toast';
import { SetsService, SetRecord, UpsertParallelPayload } from '../../../core/services/sets';

@Component({
  selector: 'app-set-builder',
  imports: [CommonModule, ReactiveFormsModule, FormsModule, RouterLink, Toast],
  providers: [MessageService],
  templateUrl: './set-builder.html',
  styleUrl: './set-builder.scss',
})
export class SetBuilder implements OnInit {
  private fb = inject(FormBuilder);
  private setsService = inject(SetsService);
  private messageService = inject(MessageService);

  readonly sports = ['Basketball', 'Baseball', 'Football', 'Soccer'];
  readonly releaseTypes = ['Hobby', 'Retail', 'FOTL'];

  sets = signal<SetRecord[]>([]);
  saving = signal(false);
  duplicateError = signal(false);
  templatePreview = signal('');

  bulkParallels = '';
  bulkChecklists = '';

  form = this.fb.group({
    name: ['', Validators.required],
    year: [new Date().getFullYear(), [Validators.required, Validators.min(1901)]],
    sport: ['Basketball', Validators.required],
    release_type: ['Hobby', Validators.required],
    ebay_search_template: ['{year} {brand} #{card_number} {player_name}'],
  });

  ngOnInit() {
    this.loadSets();
    this.form.valueChanges.subscribe(() => this.updatePreview());
    this.updatePreview();
  }

  private updatePreview() {
    const { year, name, ebay_search_template } = this.form.value;
    const template = ebay_search_template ?? '';
    const preview = template
      .replace(/{year}/g, String(year ?? ''))
      .replace(/{brand}/g, name ?? '')
      .replace(/{player_name}/g, 'Victor Wembanyama')
      .replace(/{card_number}/g, '298');
    this.templatePreview.set(preview);
  }

  private async loadSets() {
    const data = await this.setsService.getSets();
    this.sets.set(data);
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
    const isDupe = await this.setsService.checkDuplicate(name!, year!, sport!);
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
      ebay_search_template: this.form.value.ebay_search_template ?? null,
      set_slug: this.generateSlug(),
    };

    const { data: newSet, error } = await this.setsService.createSet(payload);
    this.saving.set(false);

    if (error) {
      this.messageService.add({ severity: 'error', summary: 'Error', detail: error.message });
    } else {
      const setId = newSet!.id;

      // Always create the Base Set checklist — capture its ID for parallels
      const { data: baseChecklist } = await this.setsService.createChecklist(setId, 'Base Set', null);

      // Create any additional insert checklists
      const extraChecklists = this.parseChecklists(setId);
      for (const cl of extraChecklists) {
        await this.setsService.createChecklist(cl.setId, cl.name, cl.prefix);
      }

      // Save parallels (belong to the Base Set checklist)
      let parallelCount = 0;
      if (baseChecklist) {
        const parallels = this.parseParallels(baseChecklist.id);
        parallelCount = parallels.length;
        if (parallels.length > 0) {
          await this.setsService.upsertParallels(parallels);
        }
      }

      const clNote = extraChecklists.length > 0 ? ` + ${extraChecklists.length + 1} checklists` : '';
      const parallelNote = parallelCount > 0 ? `, ${parallelCount} parallels` : '';
      this.messageService.add({ severity: 'success', summary: 'Set Created', detail: `"${name}" added${clNote}${parallelNote}.` });
      this.form.reset({
        name: '',
        year: new Date().getFullYear(),
        sport: 'Basketball',
        release_type: 'Hobby',
        ebay_search_template: '{year} {brand} #{card_number} {player_name} PSA',
      });
      this.bulkParallels = '';
      this.bulkChecklists = '';
      await this.loadSets();
    }
  }

  private parseChecklists(setId: string): { setId: string; name: string; prefix: string | null }[] {
    if (!this.bulkChecklists.trim()) return [];
    return this.bulkChecklists
      .split(',')
      .map(s => s.trim())
      .filter(s => s.length > 0)
      .map(raw => {
        const [name, prefix] = raw.split(':').map(p => p.trim());
        return { setId, name, prefix: prefix || null };
      });
  }

  private parseParallels(checklistId: string): UpsertParallelPayload[] {
    if (!this.bulkParallels.trim()) return [];
    return this.bulkParallels
      .split(',')
      .map(s => s.trim())
      .filter(s => s.length > 0)
      .map((raw, i) => {
        const parts = raw.split(':').map(p => p.trim());
        const serial_max = parts[1] ? parseInt(parts[1], 10) : null;
        return {
          checklist_id: checklistId,
          name: parts[0],
          serial_max: serial_max !== null && !isNaN(serial_max) ? serial_max : null,
          is_auto: parts[2]?.toLowerCase() === 'auto',
          color_hex: null,
          sort_order: i,
        };
      });
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
