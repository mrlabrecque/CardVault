-- Track refresh attempts (including zero-result refreshes) so cooldown applies
-- even when no rows are written to card_sold_comps.
CREATE TABLE IF NOT EXISTS public.card_comps_refresh_log (
  master_card_id UUID NOT NULL REFERENCES public.master_card_definitions(id) ON DELETE CASCADE,
  parallel_name TEXT NOT NULL,
  last_refreshed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_result_count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (master_card_id, parallel_name)
);

ALTER TABLE public.card_comps_refresh_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Auth users can read comps refresh log" ON public.card_comps_refresh_log;
CREATE POLICY "Auth users can read comps refresh log"
  ON public.card_comps_refresh_log
  FOR SELECT
  TO authenticated
  USING (true);
