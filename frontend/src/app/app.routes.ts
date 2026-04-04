import { Routes } from '@angular/router';
import { Dashboard } from './features/dashboard/dashboard';
import { CollectionList } from './features/collection/collection-list/collection-list';
import { CompsSearch } from './features/comps/comps-search/comps-search';
import { Wishlist } from './features/wishlist/wishlist/wishlist';
import { ItemDetail } from './features/collection/item-detail/item-detail';
import { Login } from './core/auth/login/login';
import { authGuard } from './core/guards/auth-guard';

export const routes: Routes = [
  { path: 'login', component: Login },
  { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
  { path: 'dashboard',     component: Dashboard,     canActivate: [authGuard] },
  { path: 'collection',    component: CollectionList, canActivate: [authGuard] },
  { path: 'collection/:id', component: ItemDetail,   canActivate: [authGuard] },
  { path: 'comps',         component: CompsSearch,   canActivate: [authGuard] },
  { path: 'wishlist',      component: Wishlist,      canActivate: [authGuard] },
  { path: '**', redirectTo: 'dashboard' },
];
