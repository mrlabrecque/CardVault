-- Expected parallel count from CardSight release.sets[].parallelCount (catalog import).
ALTER TABLE public.sets
  ADD COLUMN IF NOT EXISTS cardsight_parallel_count integer;

COMMENT ON COLUMN public.sets.cardsight_parallel_count IS
  'CardSight sets[].parallelCount from the parent release payload.';

-- Postgres cannot add/reorder view columns via CREATE OR REPLACE; drop dependents first.
DROP VIEW IF EXISTS public.catalog_release_coverage;
DROP VIEW IF EXISTS public.catalog_set_coverage;

CREATE VIEW public.catalog_set_coverage AS
SELECT
  s.id AS set_id,
  s.release_id,
  s.name AS set_name,
  s.cardsight_id,
  s.card_count AS expected_card_count,
  s.cardsight_parallel_count AS expected_parallel_count,
  COALESCE(sc.cnt, 0)::int AS vault_card_count,
  COALESCE(sp.cnt, 0)::int AS parallel_count,
  (s.cardsight_id IS NOT NULL AND btrim(s.cardsight_id) <> '') AS has_cardsight_id,
  (COALESCE(sp.cnt, 0) > 0) AS has_parallels,
  (COALESCE(sc.cnt, 0) > 0) AS has_cards,
  (
    (s.card_count IS NULL AND COALESCE(sc.cnt, 0) > 0)
    OR (s.card_count IS NOT NULL AND COALESCE(sc.cnt, 0) >= s.card_count)
  ) AS cards_complete,
  (
    (s.cardsight_parallel_count IS NULL AND COALESCE(sp.cnt, 0) > 0)
    OR (
      s.cardsight_parallel_count IS NOT NULL
      AND COALESCE(sp.cnt, 0) >= s.cardsight_parallel_count
    )
  ) AS parallels_complete
FROM public.sets s
LEFT JOIN LATERAL (
  SELECT COUNT(*)::bigint AS cnt
  FROM public.set_cards x
  WHERE x.set_id = s.id
) sc ON true
LEFT JOIN LATERAL (
  SELECT COUNT(*)::bigint AS cnt
  FROM public.set_parallels x
  WHERE x.set_id = s.id
) sp ON true;

CREATE VIEW public.catalog_release_coverage AS
SELECT
  r.id AS release_id,
  r.name AS release_name,
  r.year,
  r.sport,
  r.cardsight_id,
  COUNT(c.set_id)::int AS set_count,
  COUNT(c.set_id) FILTER (WHERE c.has_cardsight_id)::int AS sets_with_cardsight,
  COUNT(c.set_id) FILTER (WHERE c.parallels_complete)::int AS sets_with_parallels,
  COUNT(c.set_id) FILTER (WHERE c.has_cards)::int AS sets_with_cards,
  COUNT(c.set_id) FILTER (WHERE c.cards_complete)::int AS sets_cards_complete,
  COALESCE(SUM(c.expected_card_count), 0)::bigint AS expected_card_total,
  COALESCE(SUM(c.vault_card_count), 0)::bigint AS vault_card_total
FROM public.releases r
LEFT JOIN public.catalog_set_coverage c ON c.release_id = r.id
GROUP BY r.id, r.name, r.year, r.sport, r.cardsight_id;

COMMENT ON VIEW public.catalog_set_coverage IS
  'Per-set CardSight import coverage: parallels, vault card count vs sets.card_count.';

COMMENT ON VIEW public.catalog_release_coverage IS
  'Per-release rollup of catalog_set_coverage for admin backfill progress.';

GRANT SELECT ON public.catalog_set_coverage TO authenticated;
GRANT SELECT ON public.catalog_release_coverage TO authenticated;
