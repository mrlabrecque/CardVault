-- Add sport column to wishlist table
alter table wishlist
  add column if not exists sport text;
