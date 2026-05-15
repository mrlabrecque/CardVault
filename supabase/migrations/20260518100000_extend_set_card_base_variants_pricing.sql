-- Extend `set_card_base_variants` with CardHedge rollups from the underlying
-- `master_card_definitions` row (same `id` as today — the view never stored
-- prices; it only projected a subset of columns).
--
-- Note: `current_prices` references `master_card_definitions.id`. The Base migration
-- only changed `parallel_id` on existing rows — primary keys unchanged — so
-- `current_prices` rows did not need repointing.

CREATE OR REPLACE VIEW public.set_card_base_variants AS
SELECT DISTINCT ON (sc.id)
  m.id,
  sc.id AS set_card_id,
  sc.set_id,
  sc.player,
  sc.card_number,
  sc.is_rookie,
  m.is_auto,
  m.is_patch,
  m.is_ssp,
  m.serial_max,
  COALESCE(NULLIF(m.image_url, ''), sc.image_url) AS image_url,
  sc.cardsight_card_id,
  m.sales_7d,
  m.sales_30d,
  m.gain,
  m.cardhedge_id,
  m.cardhedge_fetched_at
FROM public.set_cards sc
INNER JOIN public.master_card_definitions m ON m.set_card_id = sc.id
INNER JOIN public.set_parallels p ON p.id = m.parallel_id
ORDER BY
  sc.id,
  CASE WHEN lower(trim(p.name)) = 'base' THEN 0 ELSE 1 END,
  p.sort_order NULLS LAST,
  p.name;

GRANT SELECT ON public.set_card_base_variants TO anon, authenticated;
