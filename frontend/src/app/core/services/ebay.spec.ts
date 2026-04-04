import { TestBed } from '@angular/core/testing';

import { Ebay } from './ebay';

describe('Ebay', () => {
  let service: Ebay;

  beforeEach(() => {
    TestBed.configureTestingModule({});
    service = TestBed.inject(Ebay);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });
});
