import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { TagModule } from 'primeng/tag';

@Component({
  selector: 'app-card-tags',
  imports: [CommonModule, TagModule],
  templateUrl: './card-tags.html',
})
export class CardTags {
  @Input() grade = '';
  @Input() rookie = false;
  @Input() autograph = false;
  @Input() memorabilia = false;
  /** 'default' uses colored tags; 'ghost' uses white/translucent for dark backgrounds */
  @Input() variant: 'default' | 'ghost' = 'default';
}
