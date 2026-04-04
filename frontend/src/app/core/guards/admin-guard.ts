import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from '../services/auth';

export const adminGuard: CanActivateFn = async () => {
  const auth = inject(AuthService);
  const router = inject(Router);

  const session = await auth.getSession();
  if (!session) return router.createUrlTree(['/login']);

  const { data } = await auth.getClient()
    .from('profiles')
    .select('is_app_admin')
    .eq('id', session.user.id)
    .single();

  if (!data?.is_app_admin) return router.createUrlTree(['/dashboard']);
  return true;
};
