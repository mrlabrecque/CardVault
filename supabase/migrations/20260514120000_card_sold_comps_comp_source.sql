-- Separate marketplace (eBay) comps from CardHedge grade comps so refresh-comps
-- does not delete CardHedge rows.
-- Superseded in behavior by 20260515130000 (from_market_scrape + price_source).
-- Retained for migration history on databases that already applied this revision.

ALTER TABLE public.card_sold_comps
  ADD COLUMN IF NOT EXISTS comp_source text NOT NULL DEFAULT 'ebay';

ALTER TABLE public.card_sold_comps
  DROP CONSTRAINT IF EXISTS card_sold_comps_comp_source_check;

ALTER TABLE public.card_sold_comps
  ADD CONSTRAINT card_sold_comps_comp_source_check
  CHECK (comp_source IN ('ebay', 'cardhedge'));

CREATE INDEX IF NOT EXISTS card_sold_comps_master_source_grade_idx
  ON public.card_sold_comps (master_card_id, comp_source, parallel_name, grade);

COMMENT ON COLUMN public.card_sold_comps.comp_source IS
  'Legacy: superseded by from_market_scrape + price_source (see 20260515130000).';
