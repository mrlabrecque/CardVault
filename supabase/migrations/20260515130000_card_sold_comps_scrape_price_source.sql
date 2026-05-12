-- Sold comps: distinguish Bright Data scrape rows vs pricing-API rows; store API price_source.

ALTER TABLE public.card_sold_comps
  ADD COLUMN IF NOT EXISTS from_market_scrape boolean;

ALTER TABLE public.card_sold_comps
  ADD COLUMN IF NOT EXISTS price_source text;

UPDATE public.card_sold_comps
SET from_market_scrape = true
WHERE from_market_scrape IS NULL;

ALTER TABLE public.card_sold_comps
  ALTER COLUMN from_market_scrape SET DEFAULT true;

ALTER TABLE public.card_sold_comps
  ALTER COLUMN from_market_scrape SET NOT NULL;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'card_sold_comps'
      AND column_name = 'comp_source'
  ) THEN
    UPDATE public.card_sold_comps
    SET from_market_scrape = (comp_source = 'ebay');

    ALTER TABLE public.card_sold_comps DROP CONSTRAINT IF EXISTS card_sold_comps_comp_source_check;
    DROP INDEX IF EXISTS public.card_sold_comps_master_source_grade_idx;
    ALTER TABLE public.card_sold_comps DROP COLUMN comp_source;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS card_sold_comps_master_market_scrape_idx
  ON public.card_sold_comps (master_card_id, from_market_scrape);

COMMENT ON COLUMN public.card_sold_comps.from_market_scrape IS
  'True: rows from refresh-comps Bright Data scrape; false: rows from pricing comps API (e.g. CardHedge /v1/cards/comps).';

COMMENT ON COLUMN public.card_sold_comps.price_source IS
  'Upstream feed id per sale (e.g. ebay), from CardHedge raw_prices.price_source when applicable; optional for scrape rows.';
