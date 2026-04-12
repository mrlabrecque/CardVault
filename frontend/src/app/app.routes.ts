import { Routes } from '@angular/router';
import { Dashboard } from './features/dashboard/dashboard';
import { CollectionList } from './features/collection/collection-list/collection-list';
import { CompsSearch } from './features/comps/comps-search/comps-search';
import { Wishlist } from './features/wishlist/wishlist/wishlist';
import { ItemDetail } from './features/collection/item-detail/item-detail';
import { Login } from './core/auth/login/login';
import { SetPassword } from './core/auth/set-password/set-password';
import { Scanner } from './features/scanner/scanner';
import { BulkAdd } from './features/collection/bulk-add/bulk-add';
import { CsvImport } from './features/collection/csv-import/csv-import';
import { ReleaseBuilder } from './features/admin/set-builder/set-builder';
import { ParallelManager } from './features/admin/parallel-manager/parallel-manager';
import { SetManager } from './features/admin/checklist-manager/checklist-manager';
import { PendingParallels } from './features/admin/pending-parallels/pending-parallels';
import { Tools } from './features/tools/tools';
import { authGuard } from './core/guards/auth-guard';
import { adminGuard } from './core/guards/admin-guard';

export const routes: Routes = [
  { path: 'login', component: Login },
  { path: 'set-password', component: SetPassword },
  { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
  { path: 'dashboard',     component: Dashboard,     canActivate: [authGuard] },
  { path: 'collection',    component: CollectionList, canActivate: [authGuard] },
  { path: 'collection/:id', component: ItemDetail,   canActivate: [authGuard] },
  { path: 'comps',         component: CompsSearch,   canActivate: [authGuard] },
  { path: 'wishlist',      component: Wishlist,      canActivate: [authGuard] },
  { path: 'tools',         component: Tools,         canActivate: [authGuard] },
  { path: 'scanner',       component: Scanner,       canActivate: [authGuard] },
  { path: 'bulk-add',      component: BulkAdd,       canActivate: [authGuard] },
  { path: 'import',        component: CsvImport,     canActivate: [authGuard] },
  { path: 'admin/releases',    component: ReleaseBuilder, canActivate: [adminGuard] },
  { path: 'admin/releases/:releaseId/sets/:setId/parallels', component: ParallelManager, canActivate: [adminGuard] },
  { path: 'admin/releases/:releaseId/sets', component: SetManager, canActivate: [adminGuard] },
  { path: 'admin/parallels/pending', component: PendingParallels, canActivate: [adminGuard] },
  { path: '**', redirectTo: 'dashboard' },
];
