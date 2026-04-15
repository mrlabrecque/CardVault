-- Add exclude_terms array to wishlist items for eBay search filtering
ALTER TABLE wishlist ADD COLUMN IF NOT EXISTS exclude_terms text[] DEFAULT '{}';
