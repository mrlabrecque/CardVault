import sql from '../db/db';

/**
 * Daily job: refresh current_value on user_cards using recent eBay sold comps.
 *
 * TODO (Market Movers feature): For each distinct master_card_id in user_cards,
 * fetch the last 30 days of sold comps and update current_value. Track a
 * price_history table so the Market Movers view can surface the biggest movers.
 *
 * Stub — logs intent but does nothing until the Market Movers feature is built.
 */
export async function runMarketValueJob() {
  console.log('[marketValueJob] Starting daily market value refresh…');

  const [{ count }] = await sql`SELECT COUNT(DISTINCT master_card_id)::int AS count FROM user_cards`;
  console.log(`[marketValueJob] ${count} distinct cards to refresh (not yet implemented — stub).`);
}
