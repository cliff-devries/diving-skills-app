-- =============================================
-- DIVING SKILLS — Migration v2: Airtable → Supabase Skills
-- Run this ONCE in the Supabase SQL Editor on an existing database.
-- If starting fresh, run supabase-setup.sql instead.
-- =============================================


-- =============================================
-- 1. CREATE SKILLS TABLE
-- =============================================

CREATE TABLE IF NOT EXISTS public.skills (
  id                SERIAL PRIMARY KEY,
  skill_name        TEXT NOT NULL,
  skill_level       INTEGER NOT NULL CHECK (skill_level BETWEEN 0 AND 12),
  skill_type        TEXT NOT NULL DEFAULT '',
  skill_description TEXT NOT NULL DEFAULT '',
  skill_category    TEXT NOT NULL DEFAULT '',
  video_url         TEXT,
  coaching_notes    TEXT NOT NULL DEFAULT '',
  requires_harness  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.skills ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "skills: authenticated read" ON public.skills;
DROP POLICY IF EXISTS "skills: coach write"        ON public.skills;

CREATE POLICY "skills: authenticated read"
  ON public.skills FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "skills: coach write"
  ON public.skills FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'coach'
    )
  );

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS skills_set_updated_at ON public.skills;
CREATE TRIGGER skills_set_updated_at
  BEFORE UPDATE ON public.skills
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_skills_level ON public.skills(skill_level);
CREATE INDEX IF NOT EXISTS idx_skills_type  ON public.skills(skill_type);


-- =============================================
-- 2. MIGRATE skill_completions
-- Replaces airtable_skill_id TEXT with skill_id INTEGER FK.
-- NOTE: Any existing completion rows will be deleted because there is
-- no way to automatically map old Airtable IDs to new Supabase skill IDs.
-- Populate the skills table first, then divers can re-report their skills.
-- =============================================

-- Drop existing unique constraint referencing airtable_skill_id
ALTER TABLE public.skill_completions
  DROP CONSTRAINT IF EXISTS skill_completions_diver_id_airtable_skill_id_key;

-- Delete all existing completions (Airtable IDs can't be mapped automatically)
DELETE FROM public.skill_completions;

-- Drop old column
ALTER TABLE public.skill_completions
  DROP COLUMN IF EXISTS airtable_skill_id;

-- Add new FK column
ALTER TABLE public.skill_completions
  ADD COLUMN IF NOT EXISTS skill_id INTEGER NOT NULL REFERENCES public.skills(id) ON DELETE CASCADE;

-- Add new unique constraint
ALTER TABLE public.skill_completions
  ADD CONSTRAINT skill_completions_diver_id_skill_id_key UNIQUE (diver_id, skill_id);

-- Rebuild index
DROP INDEX IF EXISTS idx_completions_skill_id;
CREATE INDEX IF NOT EXISTS idx_completions_skill_id ON public.skill_completions(skill_id);
