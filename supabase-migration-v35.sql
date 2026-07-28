-- =============================================
-- DIVING SKILLS — Migration v35: Strength & Conditioning Leaderboard
-- Run this ONCE in the Supabase SQL Editor on an existing database.
--
-- What this does:
--   1. Creates leaderboard_scores — one row per (diver, exercise), storing
--      only the diver's personal best for that exercise. A retest that
--      beats the stored score overwrites the row via upsert.
--   2. RLS: any authenticated user can read (leaderboard is visible to
--      coaches, divers, and parents). Only active coaches/super_users can
--      insert/update/delete scores.
--   3. Indexes on exercise and diver_id for leaderboard/personal-best lookups.
-- =============================================

CREATE TABLE IF NOT EXISTS public.leaderboard_scores (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  diver_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  exercise     TEXT NOT NULL,
  score        NUMERIC(8,2) NOT NULL,
  score_type   TEXT NOT NULL, -- 'reps', 'inches', 'pounds', 'rsi', 'boolean'
  recorded_by  UUID REFERENCES public.profiles(id),
  recorded_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  notes        TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (diver_id, exercise)
);

CREATE INDEX IF NOT EXISTS idx_leaderboard_scores_exercise ON public.leaderboard_scores(exercise);
CREATE INDEX IF NOT EXISTS idx_leaderboard_scores_diver_id ON public.leaderboard_scores(diver_id);

ALTER TABLE public.leaderboard_scores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "leaderboard_scores: authenticated read" ON public.leaderboard_scores;
DROP POLICY IF EXISTS "leaderboard_scores: coach insert"       ON public.leaderboard_scores;
DROP POLICY IF EXISTS "leaderboard_scores: coach update"       ON public.leaderboard_scores;
DROP POLICY IF EXISTS "leaderboard_scores: coach delete"       ON public.leaderboard_scores;

CREATE POLICY "leaderboard_scores: authenticated read"
  ON public.leaderboard_scores FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "leaderboard_scores: coach insert"
  ON public.leaderboard_scores FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE auth_user_id = auth.uid()
        AND role IN ('coach', 'super_user')
        AND status = 'active'
    )
  );

CREATE POLICY "leaderboard_scores: coach update"
  ON public.leaderboard_scores FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE auth_user_id = auth.uid()
        AND role IN ('coach', 'super_user')
        AND status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE auth_user_id = auth.uid()
        AND role IN ('coach', 'super_user')
        AND status = 'active'
    )
  );

CREATE POLICY "leaderboard_scores: coach delete"
  ON public.leaderboard_scores FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE auth_user_id = auth.uid()
        AND role IN ('coach', 'super_user')
        AND status = 'active'
    )
  );
