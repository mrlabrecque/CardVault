CREATE TABLE IF NOT EXISTS public.set_parallels (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  set_id      uuid        NOT NULL REFERENCES public.sets(id) ON DELETE CASCADE,
  name        text        NOT NULL,
  serial_max  integer,          -- null = unnumbered; 1 = 1/1
  is_auto     boolean     NOT NULL DEFAULT false,
  color_hex   text,             -- optional UI pill color e.g. '#C0C0C0'
  sort_order  integer     NOT NULL DEFAULT 0,
  created_at  timestamptz DEFAULT now(),

  UNIQUE(set_id, name)
);

ALTER TABLE public.set_parallels ENABLE ROW LEVEL SECURITY;

-- All authenticated users can read parallels
CREATE POLICY "Authenticated users can read set_parallels"
  ON public.set_parallels FOR SELECT
  TO authenticated
  USING (true);

-- Only app admins can insert
CREATE POLICY "App admins can insert set_parallels"
  ON public.set_parallels FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND is_app_admin = true
    )
  );

-- Only app admins can update
CREATE POLICY "App admins can update set_parallels"
  ON public.set_parallels FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND is_app_admin = true
    )
  );

-- Only app admins can delete
CREATE POLICY "App admins can delete set_parallels"
  ON public.set_parallels FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND is_app_admin = true
    )
  );
