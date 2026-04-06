-- Checklists: child of sets. Distinguishes Base Set from Insert subsets (e.g. Fireworks, Monopoly).
-- The `prefix` column is used by the OCR scanner to route card numbers to the right checklist
-- (e.g. prefix "F-" means card #F-12 belongs to the Fireworks checklist, not the base set).
-- A NULL prefix means the base set — card numbers have no prefix.

CREATE TABLE IF NOT EXISTS public.checklists (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  set_id     uuid        NOT NULL REFERENCES public.sets(id) ON DELETE CASCADE,
  name       text        NOT NULL,   -- e.g. "Base Set", "Fireworks", "Monopoly Money"
  prefix     text,                   -- e.g. "F-", "M-"; NULL = base set
  created_at timestamptz DEFAULT now(),

  UNIQUE(set_id, name)
);

ALTER TABLE public.checklists ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read checklists"
  ON public.checklists FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "App admins can insert checklists"
  ON public.checklists FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_app_admin = true)
  );

CREATE POLICY "App admins can update checklists"
  ON public.checklists FOR UPDATE
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_app_admin = true)
  );

CREATE POLICY "App admins can delete checklists"
  ON public.checklists FOR DELETE
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_app_admin = true)
  );

-- ROLLBACK:
-- DROP TABLE IF EXISTS public.checklists;
