import { ComponentFixture, TestBed } from '@angular/core/testing';

import { CompsSearch } from './comps-search';

describe('CompsSearch', () => {
  let component: CompsSearch;
  let fixture: ComponentFixture<CompsSearch>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [CompsSearch],
    }).compileComponents();

    fixture = TestBed.createComponent(CompsSearch);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
