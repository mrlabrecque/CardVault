import { TestBed } from '@angular/core/testing';

import { Checklist } from './checklist';

describe('Checklist', () => {
  let service: Checklist;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(Checklist);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
