-- =============================================
-- DIVING SKILLS — Migration v44: DivePractice Practice Builder support
-- Run this ONCE in the Supabase SQL Editor. Purely additive (ADD COLUMN /
-- CREATE TABLE, no drops) — existing data is untouched either way.
--
-- Background: the DivePractice nav/UI overhaul adds two genuinely new
-- pieces of plan data — multi-select Announcements and a merged
-- Practice/Competition "Practice Points" picker — plus a new Rotation
-- Templates entity (a named group of rotation "stations", each an
-- optional skill + minutes, insertable into a plan as a batch of rows).
-- The existing single-string announcements/practiceEmphasis/
-- competitionEmphasis columns and dive_practice_emphasis table are left
-- exactly as they are — the app keeps deriving them from the new
-- multi-select fields for backward compat with printPlan() and anything
-- else already reading them (see practice.html's Practice Builder code
-- for the derivation logic).
-- =============================================


-- =============================================
-- 1. PLANS: new multi-select fields
-- =============================================

ALTER TABLE public.dive_practice_plans
  ADD COLUMN IF NOT EXISTS announcement_list TEXT[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS practice_points   JSONB   NOT NULL DEFAULT '[]',
  ADD COLUMN IF NOT EXISTS notes             TEXT;


-- =============================================
-- 2. NEW TABLE: dive_practice_rotation_templates (club-wide shared)
-- Same shared-table pattern as dive_practice_groups (v42): any active
-- coach can read, only the creator can insert/update/delete their own.
-- =============================================

CREATE TABLE IF NOT EXISTS public.dive_practice_rotation_templates (
  id          TEXT PRIMARY KEY,
  coach_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  stations    JSONB NOT NULL DEFAULT '[]',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.dive_practice_rotation_templates ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_dive_practice_rotation_templates_coach_id ON public.dive_practice_rotation_templates(coach_id);

DROP POLICY IF EXISTS "dive_practice_rotation_templates: club read" ON public.dive_practice_rotation_templates;
CREATE POLICY "dive_practice_rotation_templates: club read"
  ON public.dive_practice_rotation_templates FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'coach' AND status = 'active')
  );

DROP POLICY IF EXISTS "dive_practice_rotation_templates: own insert" ON public.dive_practice_rotation_templates;
CREATE POLICY "dive_practice_rotation_templates: own insert"
  ON public.dive_practice_rotation_templates FOR INSERT
  WITH CHECK (coach_id = auth.uid());

DROP POLICY IF EXISTS "dive_practice_rotation_templates: own update" ON public.dive_practice_rotation_templates;
CREATE POLICY "dive_practice_rotation_templates: own update"
  ON public.dive_practice_rotation_templates FOR UPDATE
  USING (coach_id = auth.uid());

DROP POLICY IF EXISTS "dive_practice_rotation_templates: own delete" ON public.dive_practice_rotation_templates;
CREATE POLICY "dive_practice_rotation_templates: own delete"
  ON public.dive_practice_rotation_templates FOR DELETE
  USING (coach_id = auth.uid());
