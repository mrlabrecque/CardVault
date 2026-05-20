-- Merge duplicate `set_parallels` rows that only differ by casing of the name "Base"
-- (e.g. `Base` + `base`). UNIQUE(set_id, name) is case-sensitive, so both can exist.
-- Repoints `master_card_definitions` / `user_cards.parallel_id`, merges conflicting
-- catalog variants per `set_card`, then deletes the redundant parallel row.
--
-- Idempotent: safe to re-run (no-op when each set has at most one lower(base) row).

DO $body$
DECLARE
  v_set_id uuid;
  v_keeper uuid;
  v_loser uuid;
  r_pair record;
BEGIN
  FOR v_set_id IN
    SELECT sp.set_id
    FROM public.set_parallels sp
    WHERE lower(trim(sp.name)) = 'base'
    GROUP BY sp.set_id
    HAVING count(*) > 1
  LOOP
    SELECT sp.id
    INTO v_keeper
    FROM public.set_parallels sp
    WHERE sp.set_id = v_set_id
      AND lower(trim(sp.name)) = 'base'
    ORDER BY
      CASE WHEN sp.name = 'Base' THEN 0 ELSE 1 END,
      sp.sort_order NULLS LAST,
      sp.created_at NULLS LAST,
      sp.id
    LIMIT 1;

    IF v_keeper IS NULL THEN
      CONTINUE;
    END IF;

    FOR v_loser IN
      SELECT sp.id
      FROM public.set_parallels sp
      WHERE sp.set_id = v_set_id
        AND lower(trim(sp.name)) = 'base'
        AND sp.id <> v_keeper
    LOOP
      -- Non-conflicting: no existing master on keeper parallel for this set_card.
      UPDATE public.master_card_definitions m
      SET parallel_id = v_keeper
      WHERE m.parallel_id = v_loser
        AND NOT EXISTS (
          SELECT 1
          FROM public.master_card_definitions x
          WHERE x.set_card_id = m.set_card_id
            AND x.parallel_id = v_keeper
        );

      -- Conflicting: same set_card has masters on both loser and keeper parallels.
      FOR r_pair IN
        SELECT ml.id AS loser_master_id, mk.id AS keeper_master_id
        FROM public.master_card_definitions ml
        INNER JOIN public.master_card_definitions mk
          ON mk.set_card_id = ml.set_card_id
         AND mk.parallel_id = v_keeper
        WHERE ml.parallel_id = v_loser
      LOOP
        UPDATE public.user_cards uc
        SET master_card_id = r_pair.keeper_master_id
        WHERE uc.master_card_id = r_pair.loser_master_id;

        UPDATE public.wishlist w
        SET master_card_id = r_pair.keeper_master_id
        WHERE w.master_card_id = r_pair.loser_master_id;

        UPDATE public.card_sold_comps c
        SET master_card_id = r_pair.keeper_master_id
        WHERE c.master_card_id = r_pair.loser_master_id;

        UPDATE public.card_comps_refresh_log l
        SET master_card_id = r_pair.keeper_master_id
        WHERE l.master_card_id = r_pair.loser_master_id;

        INSERT INTO public.current_prices (master_card_id, grade, price, currency, raw, fetched_at)
        SELECT
          r_pair.keeper_master_id,
          cp.grade,
          cp.price,
          cp.currency,
          cp.raw,
          cp.fetched_at
        FROM public.current_prices cp
        WHERE cp.master_card_id = r_pair.loser_master_id
        ON CONFLICT ON CONSTRAINT current_prices_master_grade_uq DO NOTHING;

        DELETE FROM public.master_card_definitions WHERE id = r_pair.loser_master_id;
      END LOOP;

      UPDATE public.user_cards uc
      SET parallel_id = v_keeper
      WHERE uc.parallel_id = v_loser;

      DELETE FROM public.set_parallels WHERE id = v_loser;
    END LOOP;

    -- Canonical display name after merge.
    UPDATE public.set_parallels sp
    SET name = 'Base'
    WHERE sp.id = v_keeper
      AND lower(trim(sp.name)) = 'base'
      AND sp.name IS DISTINCT FROM 'Base';
  END LOOP;
END
$body$;
