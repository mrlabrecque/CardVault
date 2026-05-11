-- Portfolio movers from aggregated collection price changes (all users’ user_cards).
-- Uses user_cards.current_value vs previous_value after comps refresh; SECURITY DEFINER so
-- RLS on user_cards does not block cross-user aggregates.

CREATE OR REPLACE FUNCTION public.portfolio_movers_from_vault(p_sport text DEFAULT NULL)
RETURNS TABLE (
  player_key text,
  player_name text,
  sport text,
  card_count bigint,
  avg_current numeric,
  avg_previous numeric,
  price_change_pct double precision
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH base AS (
    SELECT
      trim(both from m.player) AS pn,
      trim(both from coalesce(r.sport::text, '')) AS spr,
      u.current_value::numeric AS cv,
      u.previous_value::numeric AS pv
    FROM public.user_cards u
    INNER JOIN public.master_card_definitions m ON m.id = u.master_card_id
    INNER JOIN public.sets s ON s.id = m.set_id
    INNER JOIN public.releases r ON r.id = s.release_id
    WHERE u.current_value IS NOT NULL
      AND u.previous_value IS NOT NULL
      AND u.previous_value > 0
      AND trim(both from coalesce(m.player, '')) <> ''
  ),
  agg AS (
    SELECT
      pn AS agg_player,
      spr AS agg_sport,
      COUNT(*)::bigint AS cnt,
      AVG(cv) AS avg_cur,
      AVG(pv) AS avg_prev
    FROM base
    GROUP BY pn, spr
  )
  SELECT
    md5(agg.agg_player || '|' || agg.agg_sport)::text AS player_key,
    agg.agg_player::text AS player_name,
    agg.agg_sport::text AS sport,
    agg.cnt AS card_count,
    round(agg.avg_cur, 2) AS avg_current,
    round(agg.avg_prev, 2) AS avg_previous,
    CASE
      WHEN agg.avg_prev > 0 THEN
        ((agg.avg_cur - agg.avg_prev) / agg.avg_prev * 100)::double precision
      ELSE 0::double precision
    END AS price_change_pct
  FROM agg
  WHERE (p_sport IS NULL OR trim(both from agg.agg_sport) = trim(both from p_sport));
$$;

COMMENT ON FUNCTION public.portfolio_movers_from_vault(text) IS
  'Portfolio movers: avg(current_value) vs avg(previous_value) across all collections per player/sport; optional sport filter (releases.sport).';

REVOKE ALL ON FUNCTION public.portfolio_movers_from_vault(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.portfolio_movers_from_vault(text) TO authenticated;
