alter table user_cards
  add column if not exists value_refreshed_at timestamptz,
  add column if not exists weekly_price_check boolean not null default false;

-- Index for the cron job's daily-tier query (top cards by value)
create index if not exists user_cards_current_value_idx on user_cards (current_value desc nulls last);

-- Index for the weekly-tier query
create index if not exists user_cards_weekly_check_idx on user_cards (weekly_price_check, value_refreshed_at) where weekly_price_check = true;
