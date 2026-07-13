-- =============================================
-- DIVING SKILLS — Migration v32: Skill star ratings
-- Run this ONCE in the Supabase SQL Editor on an existing database.
--
-- What this does:
--   1. Creates skill_ratings — one row per (skill, coach), rating 1.0-5.0
--      in 0.5 increments. Coaches upsert their own rating; averages are
--      computed client-side from all rows for a skill.
--   2. RLS: any authenticated user can read (to show averages). Only
--      active coaches/super_users can insert/update their own rating row.
--   3. Index on skill_id for fast average/count lookups.
-- =============================================

CREATE TABLE IF NOT EXISTS public.skill_ratings (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  skill_id   INTEGER NOT NULL REFERENCES public.skills(id) ON DELETE CASCADE,
  coach_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rating     NUMERIC(2,1) NOT NULL CHECK (rating >= 1.0 AND rating <= 5.0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (skill_id, coach_id)
);

CREATE INDEX IF NOT EXISTS idx_skill_ratings_skill_id ON public.skill_ratings(skill_id);

-- public.set_updated_at() already exists (created in migration v2).
DROP TRIGGER IF EXISTS skill_ratings_set_updated_at ON public.skill_ratings;
CREATE TRIGGER skill_ratings_set_updated_at
  BEFORE UPDATE ON public.skill_ratings
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

ALTER TABLE public.skill_ratings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "skill_ratings: authenticated read" ON public.skill_ratings;
DROP POLICY IF EXISTS "skill_ratings: coach insert own"   ON public.skill_ratings;
DROP POLICY IF EXISTS "skill_ratings: coach update own"   ON public.skill_ratings;

CREATE POLICY "skill_ratings: authenticated read"
  ON public.skill_ratings FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "skill_ratings: coach insert own"
  ON public.skill_ratings FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = coach_id
        AND auth_user_id = auth.uid()
        AND role IN ('coach', 'super_user')
        AND status = 'active'
    )
  );

CREATE POLICY "skill_ratings: coach update own"
  ON public.skill_ratings FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = coach_id
        AND auth_user_id = auth.uid()
        AND role IN ('coach', 'super_user')
        AND status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = coach_id
        AND auth_user_id = auth.uid()
        AND role IN ('coach', 'super_user')
        AND status = 'active'
    )
  );
