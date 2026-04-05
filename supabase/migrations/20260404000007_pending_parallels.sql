CREATE TABLE IF NOT EXISTS public.pending_parallels (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  set_id           uuid        NOT NULL REFERENCES public.sets(id) ON DELETE CASCADE,
  name             text        NOT NULL,
  submitted_by     uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  submission_count integer     NOT NULL DEFAULT 1,
  status           text        NOT NULL DEFAULT 'pending'
                               CHECK (status IN ('pending', 'approved', 'dismissed')),
  created_at       timestamptz DEFAULT now(),

  UNIQUE(set_id, name)
);

ALTER TABLE public.pending_parallels ENABLE ROW LEVEL SECURITY;

-- Any authenticated user can submit a pending parallel
CREATE POLICY "Authenticated users can insert pending_parallels"
  ON public.pending_parallels FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Any authenticated user can increment the submission count on conflict
-- (the upsert UPDATE path also needs UPDATE permission)
CREATE POLICY "Authenticated users can update submission_count"
  ON public.pending_parallels FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Only app admins can read the full queue
CREATE POLICY "App admins can read pending_parallels"
  ON public.pending_parallels FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND is_app_admin = true
    )
  );

-- Only app admins can delete (dismiss)
CREATE POLICY "App admins can delete pending_parallels"
  ON public.pending_parallels FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND is_app_admin = true
    )
  );

-- ── RPC: submit or increment a pending parallel ──────────────────────────────
-- Inserts a new pending parallel, or increments submission_count if it already
-- exists (and resets status to 'pending' in case it was previously dismissed).
CREATE OR REPLACE FUNCTION public.submit_pending_parallel(
  p_set_id  uuid,
  p_name    text,
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.pending_parallels (set_id, name, submitted_by, submission_count, status)
  VALUES (p_set_id, p_name, p_user_id, 1, 'pending')
  ON CONFLICT (set_id, name)
  DO UPDATE SET
    submission_count = pending_parallels.submission_count + 1,
    status = CASE
      WHEN pending_parallels.status = 'dismissed' THEN 'pending'
      ELSE pending_parallels.status
    END;
END;
$$;
