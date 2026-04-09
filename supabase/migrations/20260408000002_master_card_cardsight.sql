-- Add CardSight reference columns to master_card_definitions.
-- cardsight_card_id: unique external ID for deduplication on re-import.
-- image_url: lazily populated on first user add; stored in Supabase Storage (card-images bucket).
-- Also creates the card-images storage bucket (public, so image URLs are directly accessible).

ALTER TABLE public.master_card_definitions
  ADD COLUMN IF NOT EXISTS cardsight_card_id TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS image_url         TEXT;

-- Create the card-images bucket for lazy card image storage.
INSERT INTO storage.buckets (id, name, public)
VALUES ('card-images', 'card-images', true)
ON CONFLICT (id) DO NOTHING;

-- Allow all authenticated users to read card images.
DROP POLICY IF EXISTS "card_images_read" ON storage.objects;
CREATE POLICY "card_images_read"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'card-images');

-- Allow the service role (backend) to upload card images.
DROP POLICY IF EXISTS "card_images_insert" ON storage.objects;
CREATE POLICY "card_images_insert"
  ON storage.objects FOR INSERT
  TO service_role
  WITH CHECK (bucket_id = 'card-images');

DROP POLICY IF EXISTS "card_images_update" ON storage.objects;
CREATE POLICY "card_images_update"
  ON storage.objects FOR UPDATE
  TO service_role
  USING (bucket_id = 'card-images');

-- ROLLBACK:
-- DROP POLICY IF EXISTS "card_images_update" ON storage.objects;
-- DROP POLICY IF EXISTS "card_images_insert" ON storage.objects;
-- DROP POLICY IF EXISTS "card_images_read"   ON storage.objects;
-- DELETE FROM storage.buckets WHERE id = 'card-images';
-- ALTER TABLE public.master_card_definitions DROP COLUMN IF EXISTS image_url;
-- ALTER TABLE public.master_card_definitions DROP COLUMN IF EXISTS cardsight_card_id;
