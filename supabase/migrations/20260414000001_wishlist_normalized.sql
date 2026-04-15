-- Normalize wishlist table with explicit card attribute columns.
-- card_details jsonb is kept for backwards-compat but new columns are the source of truth.

alter table wishlist
  add column if not exists player        text,
  add column if not exists year          int,
  add column if not exists set_name      text,
  add column if not exists parallel      text,
  add column if not exists card_number   text,
  add column if not exists is_rookie     boolean not null default false,
  add column if not exists is_auto       boolean not null default false,
  add column if not exists is_patch      boolean not null default false,
  add column if not exists serial_max    int,
  add column if not exists grade         text,
  add column if not exists ebay_query    text,
  add column if not exists last_seen_price  decimal(10,2),
  add column if not exists last_checked_at  timestamptz;
