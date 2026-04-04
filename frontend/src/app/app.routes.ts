import { Routes } from '@angular/router';
import { Dashboard } from './features/dashboard/dashboard';
import { CollectionList } from './features/collection/collection-list/collection-list';
import { CompsSearch } from './features/comps/comps-search/comps-search';
import { Wishlist } from './features/wishlist/wishlist/wishlist';
import { ItemDetail } from './features/collection/item-detail/item-detail';

export const routes: Routes = [
  { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
  { path: 'dashboard', component: Dashboard },
  { path: 'collection', component: CollectionList },
  { path: 'collection/:id', component: ItemDetail },
  { path: 'comps', component: CompsSearch },
  { path: 'wishlist', component: Wishlist },
  { path: '**', redirectTo: 'dashboard' },
];
