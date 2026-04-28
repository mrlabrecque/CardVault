-- Add catalog relationship fields to wishlist table
alter table wishlist
  add column if not exists master_card_id uuid references master_card_definitions(id) on delete set null,
  add column if not exists release_id uuid references releases(id) on delete set null,
  add column if not exists set_id uuid references sets(id) on delete set null;
