import { Component, inject, signal, OnInit } from '@angular/core';
import { ReactiveFormsModule, FormBuilder, Validators } from '@angular/forms';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { MessageService } from 'primeng/api';
import { Toast } from 'primeng/toast';
import { SetsService, SetRecord } from '../../../core/services/sets';

@Component({
  selector: 'app-set-builder',
  imports: [CommonModule, ReactiveFormsModule, RouterLink, Toast],
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

    const { error } = await this.setsService.createSet(payload);
    this.saving.set(false);

    if (error) {
      this.messageService.add({ severity: 'error', summary: 'Error', detail: error.message });
    } else {
      this.messageService.add({ severity: 'success', summary: 'Set Created', detail: `"${name}" added successfully.` });
      this.form.reset({
        name: '',
        year: new Date().getFullYear(),
        sport: 'Basketball',
        release_type: 'Hobby',
        ebay_search_template: '{year} {brand} #{card_number} {player_name} PSA',
      });
      await this.loadSets();
    }
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
