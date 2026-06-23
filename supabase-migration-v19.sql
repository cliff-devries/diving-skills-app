-- =============================================
-- DIVING SKILLS — Migration v19: Testing System
-- Run this ONCE in the Supabase SQL Editor on an existing database.
-- Safe to re-run: columns use IF NOT EXISTS, policies use DROP IF EXISTS.
--
-- What this does:
--   1. Adds latest_score, latest_test_date, level_designation to
--      skill_completions — updated each time a diver is tested.
--   2. Creates the level_completions table — one row per diver per level,
--      storing the overall average score, designation, and session notes.
-- =============================================


-- =============================================
-- 1. EXTEND skill_completions
-- =============================================

ALTER TABLE public.skill_completions
  ADD COLUMN IF NOT EXISTS latest_score      NUMERIC(3,1),
  ADD COLUMN IF NOT EXISTS latest_test_date  DATE,
  ADD COLUMN IF NOT EXISTS level_designation TEXT
    CHECK (level_designation IN ('bronze', 'silver', 'gold'));


-- =============================================
-- 2. CREATE level_completions TABLE
--    One row per (diver, level) — upserted on each test session.
--    Tracks the most recent test outcome for a full level.
-- =============================================

CREATE TABLE IF NOT EXISTS public.level_completions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  diver_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  level         INTEGER NOT NULL CHECK (level BETWEEN 0 AND 12),
  completed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  average_score NUMERIC(4,2),
  designation   TEXT CHECK (designation IN ('bronze', 'silver', 'gold')),
  notes         TEXT,
  coach_id      UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (diver_id, level)
);

ALTER TABLE public.level_completions ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_level_completions_diver ON public.level_completions(diver_id);


-- =============================================
-- 3. RLS POLICIES FOR level_completions
-- =============================================

DROP POLICY IF EXISTS "level_completions: diver read own"         ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: coach manages roster"   ON public.level_completions;
DROP POLICY IF EXISTS "level_completions: parent reads linked"    ON public.level_completions;

CREATE POLICY "level_completions: diver read own"
  ON public.level_completions FOR SELECT
  USING (auth.uid() = diver_id);

CREATE POLICY "level_completions: coach manages roster"
  ON public.level_completions FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = level_completions.diver_id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = level_completions.diver_id
    )
  );

CREATE POLICY "level_completions: parent reads linked"
  ON public.level_completions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.parent_diver
      WHERE parent_diver.parent_id = auth.uid()
        AND parent_diver.diver_id  = level_completions.diver_id
    )
  );
