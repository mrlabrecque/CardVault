-- Pending sets queue — mirrors the pending_parallels pattern.
-- When the OCR scanner encounters a year/brand not in the DB, it queues a pending_set
-- instead of writing directly to `sets` (which is admin-only).
-- Admins review, then promote to `sets` (and optionally create the first Base checklist).

CREATE TABLE IF NOT EXISTS public.pending_sets (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  name             text        NOT NULL,
  year             integer     NOT NULL CHECK (year > 1900),
  sport            text        NOT NULL,
  release_type     text        NOT NULL DEFAULT 'Hobby',
  submitted_by     uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  submission_count integer     NOT NULL DEFAULT 1,
  status           text        NOT NULL DEFAULT 'pending'
                               CHECK (status IN ('pending', 'approved', 'dismissed')),
  created_at       timestamptz DEFAULT now(),
  updated_at       timestamptz DEFAULT now(),

  UNIQUE(name, year, sport)   -- dedupe: same submission increments count instead
);

ALTER TABLE public.pending_sets ENABLE ROW LEVEL SECURITY;

-- Any authenticated user can submit a pending set (INSERT)
CREATE POLICY "Authenticated users can submit pending sets"
  ON public.pending_sets FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = submitted_by);

-- Any authenticated user can increment submission_count on existing pending rows (UPDATE count only)
CREATE POLICY "Authenticated users can increment pending set count"
  ON public.pending_sets FOR UPDATE
  TO authenticated
  USING (status = 'pending');

-- Only admins can read, approve, or dismiss
CREATE POLICY "App admins can read pending sets"
  ON public.pending_sets FOR SELECT
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_app_admin = true)
  );

CREATE POLICY "App admins can delete pending sets"
  ON public.pending_sets FOR DELETE
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_app_admin = true)
  );

CREATE OR REPLACE FUNCTION update_pending_sets_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER pending_sets_updated_at
  BEFORE UPDATE ON public.pending_sets
  FOR EACH ROW EXECUTE FUNCTION update_pending_sets_updated_at();

-- ROLLBACK:
-- DROP TRIGGER IF EXISTS pending_sets_updated_at ON public.pending_sets;
-- DROP FUNCTION IF EXISTS update_pending_sets_updated_at();
-- DROP TABLE IF EXISTS public.pending_sets;
