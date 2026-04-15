import sql from '../db/db';
import { searchActiveListings } from '../services/ebay.service';

const MAX_MATCHES = 5;

/**
 * Checks active eBay listings for wishlist items.
 * Pass a userId to check only that user's items (manual check);
 * omit to check all users (scheduled cron).
 *
 * For each item:
 *  - Searches eBay active listings (BIN + auctions) at or below target_price
 *  - Clears old wishlist_matches for that item, inserts top MAX_MATCHES by price
 *  - Updates last_seen_price, last_checked_at, alert_status = 'triggered' | 'active'
 */
export async function runAlertJob(userId?: string): Promise<{ checked: number; triggered: number }> {
  const scope = userId ? `user ${userId}` : 'all users';
  console.log(`[alertJob] Starting wishlist price check for ${scope}…`);

  const items = userId
    ? await sql`
        SELECT id, ebay_query, exclude_terms, dismissed_ebay_ids, target_price, alert_status
        FROM wishlist
        WHERE user_id = ${userId}
          AND alert_status IN ('active', 'triggered')
          AND ebay_query IS NOT NULL
          AND target_price IS NOT NULL`
    : await sql`
        SELECT id, ebay_query, exclude_terms, dismissed_ebay_ids, target_price, alert_status
        FROM wishlist
        WHERE alert_status IN ('active', 'triggered')
          AND ebay_query IS NOT NULL
          AND target_price IS NOT NULL`;

  if (items.length === 0) {
    console.log('[alertJob] No active wishlist items to check.');
    return { checked: 0, triggered: 0 };
  }

  console.log(`[alertJob] Checking ${items.length} wishlist items…`);

  let newlyTriggered = 0;

  for (const item of items) {
    try {
      const exclusions = (item.exclude_terms ?? []) as string[];
      const queryWithExclusions = exclusions.length > 0
        ? `${item.ebay_query} ${exclusions.map((t: string) => `-"${t}"`).join(' ')}`
        : item.ebay_query;
      const dismissed = (item.dismissed_ebay_ids ?? []) as string[];
      const allListings = await searchActiveListings(queryWithExclusions, item.target_price);
      const listings = dismissed.length > 0
        ? allListings.filter(l => !dismissed.includes(l.itemId))
        : allListings;
      const now = new Date().toISOString();

      // Always clear stale matches for this item first
      await sql`DELETE FROM wishlist_matches WHERE wishlist_id = ${item.id}`;

      if (listings.length > 0) {
        const cheapest = listings.sort((a, b) => a.price - b.price);
        const top = cheapest.slice(0, MAX_MATCHES);

        // Insert fresh matches
        await sql`
          INSERT INTO wishlist_matches ${sql(top.map(l => ({
            wishlist_id:  item.id,
            ebay_item_id: l.itemId || null,
            title:        l.title,
            price:        l.price,
            listing_type: l.listingType,
            url:          l.url || null,
            image_url:    l.imageUrl || null,
            found_at:     now,
          })))}`;

        const wasAlreadyTriggered = item.alert_status === 'triggered';

        await sql`
          UPDATE wishlist SET
            last_seen_price = ${cheapest[0].price},
            last_checked_at = ${now},
            alert_status    = 'triggered'
          WHERE id = ${item.id}`;

        if (!wasAlreadyTriggered) newlyTriggered++;
        console.log(`[alertJob] ✓ ${top.length} match(es) for item ${item.id} — cheapest $${cheapest[0].price}`);
      } else {
        // No matches — reset triggered → active and clear stale price
        await sql`
          UPDATE wishlist SET
            last_seen_price = NULL,
            last_checked_at = ${now},
            alert_status    = CASE WHEN alert_status = 'triggered' THEN 'active' ELSE alert_status END
          WHERE id = ${item.id}`;

        console.log(`[alertJob] ✗ No match for item ${item.id} ("${item.ebay_query}")`);
      }

      // Brief pause to avoid hammering the eBay API
      await new Promise(r => setTimeout(r, 300));
    } catch (e: any) {
      console.error(`[alertJob] Error checking item ${item.id}:`, e.message);
    }
  }

  console.log(`[alertJob] Done. ${items.length} checked, ${newlyTriggered} newly triggered.`);
  return { checked: items.length, triggered: newlyTriggered };
}
