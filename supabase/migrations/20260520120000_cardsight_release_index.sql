-- CardSight release list cache for admin catalog (avoids re-paginating /v1/catalog/releases every load).

CREATE TABLE public.cardsight_release_index (
  cardsight_id text PRIMARY KEY,
  segment      text NOT NULL,
  sport        text NOT NULL,
  name         text NOT NULL,
  year         int,
  synced_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX cardsight_release_index_sport_year_name_idx
  ON public.cardsight_release_index (sport, year DESC NULLS LAST, name);

CREATE INDEX cardsight_release_index_segment_synced_idx
  ON public.cardsight_release_index (segment, synced_at DESC);

CREATE TABLE public.cardsight_segment_sync (
  segment         text PRIMARY KEY,
  sport           text NOT NULL,
  release_count   int NOT NULL DEFAULT 0,
  last_synced_at  timestamptz,
  last_sync_error text
);

ALTER TABLE public.cardsight_release_index ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cardsight_segment_sync ENABLE ROW LEVEL SECURITY;

-- Read-only for authenticated users; writes via service role in edge functions.
CREATE POLICY cardsight_release_index_select ON public.cardsight_release_index
  FOR SELECT TO authenticated USING (true);

CREATE POLICY cardsight_segment_sync_select ON public.cardsight_segment_sync
  FOR SELECT TO authenticated USING (true);
