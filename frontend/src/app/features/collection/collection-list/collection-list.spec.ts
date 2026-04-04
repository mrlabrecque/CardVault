import { ComponentFixture, TestBed } from '@angular/core/testing';

import { CollectionList } from './collection-list';

describe('CollectionList', () => {
  let component: CollectionList;
  let fixture: ComponentFixture<CollectionList>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [CollectionList],
    }).compileComponents();

    fixture = TestBed.createComponent(CollectionList);
    component = fixture.componentInstance;
    await fixture.whenStable();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
