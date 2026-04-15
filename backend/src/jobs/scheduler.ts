import cron from 'node-cron';
import { runAlertJob } from './alertJob';
import { runMarketValueJob } from './marketValueJob';

/**
 * Central job registry. Add new jobs here — each job is a plain async function
 * in its own file; this file just schedules them.
 *
 * Cron syntax: second(opt) minute hour day month weekday
 */
export function startScheduler() {
  // ── Wishlist price alerts — every hour ──────────────────────────────────────
  cron.schedule('0 * * * *', async () => {
    try { await runAlertJob(); }
    catch (e: any) { console.error('[scheduler] alertJob crashed:', e.message); }
  });

  // ── Market value refresh — daily at 3am ET ──────────────────────────────────
  cron.schedule('0 3 * * *', async () => {
    try { await runMarketValueJob(); }
    catch (e: any) { console.error('[scheduler] marketValueJob crashed:', e.message); }
  }, { timezone: 'America/New_York' });

  console.log('[scheduler] Jobs registered: alertJob (hourly), marketValueJob (daily 3am ET)');
}
