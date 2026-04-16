CREATE TABLE comps_cache (
  query      text        PRIMARY KEY,
  items      jsonb       NOT NULL DEFAULT '[]',
  fetched_at timestamptz NOT NULL DEFAULT now()
);
