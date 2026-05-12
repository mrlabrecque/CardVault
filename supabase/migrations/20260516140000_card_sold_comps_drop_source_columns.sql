-- Sold comps: single stream per master + parallel + grade; no scrape/API column split.

DROP INDEX IF EXISTS public.card_sold_comps_master_market_scrape_idx;
DROP INDEX IF EXISTS public.card_sold_comps_master_source_grade_idx;

ALTER TABLE public.card_sold_comps DROP COLUMN IF EXISTS from_market_scrape;
ALTER TABLE public.card_sold_comps DROP COLUMN IF EXISTS price_source;
ALTER TABLE public.card_sold_comps DROP COLUMN IF EXISTS comp_source;
