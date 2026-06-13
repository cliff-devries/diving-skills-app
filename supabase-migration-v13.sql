-- =============================================
-- DIVING SKILLS — Migration v13: Add photo_url to skills
-- Run this ONCE in the Supabase SQL Editor on an existing database.
--
-- What this does:
--   1. Adds a nullable photo_url column to skills (defaults to NULL —
--      most skills won't have a photo).
--   2. Fixes the "skills: coach write" RLS policy, which compared
--      profiles.id to auth.uid() and could never match (profiles.id is
--      a generated UUID, not the auth user id). Coaches now need write
--      access to skills to use the new skill edit form.
-- =============================================

ALTER TABLE public.skills ADD COLUMN IF NOT EXISTS photo_url TEXT;

DROP POLICY IF EXISTS "skills: coach write" ON public.skills;

CREATE POLICY "skills: coach write"
  ON public.skills FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE auth_user_id = auth.uid() AND role = 'coach'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE auth_user_id = auth.uid() AND role = 'coach'
    )
  );
