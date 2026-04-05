import { Routes } from '@angular/router';
import { Dashboard } from './features/dashboard/dashboard';
import { CollectionList } from './features/collection/collection-list/collection-list';
import { CompsSearch } from './features/comps/comps-search/comps-search';
import { Wishlist } from './features/wishlist/wishlist/wishlist';
import { ItemDetail } from './features/collection/item-detail/item-detail';
import { Login } from './core/auth/login/login';
import { SetBuilder } from './features/admin/set-builder/set-builder';
import { ParallelManager } from './features/admin/parallel-manager/parallel-manager';
import { PendingParallels } from './features/admin/pending-parallels/pending-parallels';
import { authGuard } from './core/guards/auth-guard';
import { adminGuard } from './core/guards/admin-guard';

export const routes: Routes = [
  { path: 'login', component: Login },
  { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
  { path: 'dashboard',     component: Dashboard,     canActivate: [authGuard] },
  { path: 'collection',    component: CollectionList, canActivate: [authGuard] },
  { path: 'collection/:id', component: ItemDetail,   canActivate: [authGuard] },
  { path: 'comps',         component: CompsSearch,   canActivate: [authGuard] },
  { path: 'wishlist',      component: Wishlist,      canActivate: [authGuard] },
  { path: 'admin/sets',    component: SetBuilder,    canActivate: [adminGuard] },
  { path: 'admin/sets/:setId/parallels', component: ParallelManager, canActivate: [adminGuard] },
  { path: 'admin/parallels/pending', component: PendingParallels, canActivate: [adminGuard] },
  { path: '**', redirectTo: 'dashboard' },
];
