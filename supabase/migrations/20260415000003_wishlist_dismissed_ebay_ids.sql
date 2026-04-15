-- Store permanently dismissed eBay listing IDs per wishlist item
ALTER TABLE wishlist ADD COLUMN IF NOT EXISTS dismissed_ebay_ids text[] DEFAULT '{}';
