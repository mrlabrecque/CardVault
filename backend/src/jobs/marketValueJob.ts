import sql from '../db/db';
import { searchSoldListings } from '../services/ebay.service';
import { buildCardEbayQuery, parseAndFilter, resolveSaleType } from '../services/comps.service';

/**
 * Daily job: refresh current_value on every user_card using eBay sold comps.
 *
 * Groups by unique (master_card_id, parallel_name, is_graded, grader, grade_value)
 * so the same card variant is only fetched once even if multiple users own it.
 * Updates current_value and replaces card_sold_comps for every matching user_card.
 */
export async function runMarketValueJob(): Promise<{ processed: number; updated: number; errors: number }> {
  console.log('[marketValueJob] Starting daily market value refresh…');

  // Fetch every distinct card variant with the data needed to build an eBay query
  const variants = await sql`
    SELECT
      MIN(uc.id)                                       AS sample_card_id,
      ARRAY_AGG(uc.id)                                 AS user_card_ids,
      uc.master_card_id,
      uc.parallel_name                                 AS parallel_type,
      uc.is_graded,
      uc.grader,
      uc.grade_value,
      COALESCE(mcd.player,      uc.player)             AS player,
      COALESCE(mcd.card_number, uc.card_number)        AS card_number,
      COALESCE(mcd.is_rookie,   uc.is_rookie)          AS is_rookie,
      COALESCE(mcd.is_auto,     uc.is_auto)            AS is_auto,
      COALESCE(mcd.is_patch,    uc.is_patch)           AS is_patch,
      mcd.serial_max,
      r.name                                           AS release_name,
      s.name                                           AS set_name,
      r.year,
      r.sport
    FROM user_cards uc
    LEFT JOIN master_card_definitions mcd ON mcd.id = uc.master_card_id
    LEFT JOIN sets s    ON s.id    = COALESCE(mcd.set_id, uc.set_id)
    LEFT JOIN releases r ON r.id   = s.release_id
    GROUP BY
      uc.master_card_id, uc.parallel_name, uc.is_graded, uc.grader, uc.grade_value,
      mcd.player, uc.player,
      mcd.card_number, uc.card_number,
      mcd.is_rookie, uc.is_rookie,
      mcd.is_auto, uc.is_auto,
      mcd.is_patch, uc.is_patch,
      mcd.serial_max,
      r.name, s.name, r.year, r.sport
  `;

  if (variants.length === 0) {
    console.log('[marketValueJob] No cards to refresh.');
    return { processed: 0, updated: 0, errors: 0 };
  }

  console.log(`[marketValueJob] ${variants.length} distinct card variants to refresh…`);

  let updated = 0;
  let errors  = 0;

  for (const variant of variants) {
    const cardIds: string[] = variant.user_card_ids;
    try {
      const query = buildCardEbayQuery(variant);
      if (!query.trim()) {
        console.log(`[marketValueJob] Skipping variant — empty query`);
        continue;
      }

      const { items: raw } = await searchSoldListings(query);
      const items = parseAndFilter(raw, query, /* strictWords */ true);

      const prices = items
        .map((item: any) => parseFloat(item?.price?.value ?? '0'))
        .filter((p: number) => p > 0);

      const avgValue = prices.length > 0
        ? prices.reduce((sum: number, p: number) => sum + p, 0) / prices.length
        : 0;

      // Update current_value for all user_cards in this variant group
      await sql`
        UPDATE user_cards
        SET current_value = ${avgValue}
        WHERE id = ANY(${cardIds}::uuid[])
      `;

      // Replace sold comps for each card in the group
      await sql`DELETE FROM card_sold_comps WHERE user_card_id = ANY(${cardIds}::uuid[])`;

      if (items.length > 0) {
        const rows = cardIds.flatMap(cardId =>
          items.map((item: any) => ({
            user_card_id: cardId,
            ebay_item_id: item.itemId ?? null,
            title:        item.title ?? '',
            price:        parseFloat(item?.price?.value ?? '0'),
            currency:     item?.price?.currency ?? 'USD',
            sale_type:    resolveSaleType(item.buyingOptions ?? []),
            sold_at:      item.itemEndDate ?? null,
            url:          item.itemWebUrl ?? null,
          }))
        );
        await sql`INSERT INTO card_sold_comps ${sql(rows)}`;
      }

      console.log(`[marketValueJob] ✓ "${query}" — ${prices.length} comps, avg $${avgValue.toFixed(2)} (${cardIds.length} card${cardIds.length > 1 ? 's' : ''} updated)`);
      updated += cardIds.length;
    } catch (e: any) {
      console.error(`[marketValueJob] ✗ Error for variant (${cardIds.join(', ')}):`, e.message);
      errors++;
    }

    // Brief pause to avoid hammering the eBay API
    await new Promise(r => setTimeout(r, 350));
  }

  console.log(`[marketValueJob] Done. ${updated} cards updated, ${errors} errors.`);
  return { processed: variants.length, updated, errors };
}
