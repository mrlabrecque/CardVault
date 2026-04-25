-- Create market_movers_snapshots table for weekly price/volume snapshots
CREATE TABLE market_movers_snapshots (
  id              uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  top_player_id   uuid NOT NULL REFERENCES top_players(id) ON DELETE CASCADE,
  avg_price       numeric(10,2) NOT NULL,
  comp_count      integer NOT NULL DEFAULT 0,  -- qty sold on eBay
  snapshot_week   date NOT NULL,               -- Monday of ISO week (dedup key)
  query           text,                        -- Scrapechain query used
  created_at      timestamptz DEFAULT now()
);

CREATE UNIQUE INDEX ON market_movers_snapshots(top_player_id, snapshot_week);
CREATE INDEX ON market_movers_snapshots(top_player_id, snapshot_week DESC);

ALTER TABLE market_movers_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auth users read market snapshots"
  ON market_movers_snapshots FOR SELECT TO authenticated USING (true);
