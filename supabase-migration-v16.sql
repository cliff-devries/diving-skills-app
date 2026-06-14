-- =============================================
-- DIVING SKILLS — Migration v16: Add club_settings table
-- Run this ONCE in the Supabase SQL Editor on an existing database.
--
-- What this does:
--   1. Creates a club_settings table for manually-entered, club-wide
--      values (e.g. USA Diving / AAU Diving team rankings) shown on
--      the coach dashboard. Reusable for future club-wide settings.
--   2. All authenticated users can read settings; only coaches can
--      insert/update/delete them.
-- =============================================

CREATE TABLE IF NOT EXISTS public.club_settings (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  setting_key   TEXT NOT NULL UNIQUE,
  setting_value TEXT,
  updated_by    UUID REFERENCES public.profiles(id),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.club_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "club_settings: authenticated read" ON public.club_settings;
DROP POLICY IF EXISTS "club_settings: coach write"        ON public.club_settings;

CREATE POLICY "club_settings: authenticated read"
  ON public.club_settings FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "club_settings: coach write"
  ON public.club_settings FOR ALL
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
