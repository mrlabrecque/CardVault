-- Create top_players table for market movers feature
CREATE TABLE top_players (
  id             uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name           text NOT NULL,
  sport          text NOT NULL,  -- 'NBA', 'NFL', 'MLB', 'NHL'
  espn_id        text,           -- ESPN athlete ID for dedup
  created_at     timestamptz DEFAULT now(),
  last_synced_at timestamptz
);

CREATE UNIQUE INDEX top_players_espn_id_idx ON top_players(espn_id);
CREATE INDEX top_players_sport_idx ON top_players(sport);

ALTER TABLE top_players ENABLE ROW LEVEL SECURITY;

CREATE POLICY "auth users read top players"
  ON top_players FOR SELECT TO authenticated USING (true);
