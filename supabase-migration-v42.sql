-- =============================================
-- DIVING SKILLS — Migration v42: DivePractice flat club-wide architecture
-- Run this ONCE in the Supabase SQL Editor on an existing database.
--
-- Background: DivePractice (practice.html) was built around a per-coach
-- multi-team model (dive_practice_teams / team_id on every child table).
-- In practice a club has ONE shared skill/plan library used by several
-- coaches, and the team model caused real bugs (duplicate-team / "plans
-- missing" issues from an earlier migration). This migration flattens
-- everything: skills, locations, announcements, quotes, categories,
-- skill blocks, and notes become club-wide shared data (any active coach
-- can read all of it, but only edit/delete their own entries); practice
-- plans gain `groups` (practice-group tags) and `visibility` instead of
-- team scoping.
--
-- ** DESTRUCTIVE ** — dive_practice_teams / _players / _player_groups /
-- _rosters are dropped with CASCADE. This permanently deletes any data
-- in those tables. Confirmed intentional per the coach's explicit request.
--
-- Schema notes:
--   - There is no 'super_user' role value — profiles_role_check only
--     allows ('coach','diver','parent','pending_coach'). "Super user" is
--     the separate boolean profiles.is_super_user, already added in
--     supabase-migration-v25.sql. RLS below uses role='coach' for
--     "any active coach" and is_super_user=true for the superuser tier.
--   - dive_practice_groups is a NEW table, not present in the original
--     multi-team schema — it backs the plan-level "Practice Groups"
--     multi-select and the Settings "Club Groups" management list. Same
--     shared-table RLS pattern as skills/categories/etc.
-- =============================================


-- =============================================
-- 1. DROP team_id FROM SHARED TABLES
-- =============================================

ALTER TABLE public.dive_practice_categories    DROP COLUMN IF EXISTS team_id;
ALTER TABLE public.dive_practice_skills        DROP COLUMN IF EXISTS team_id;
ALTER TABLE public.dive_practice_skill_blocks  DROP COLUMN IF EXISTS team_id;
ALTER TABLE public.dive_practice_locations     DROP COLUMN IF EXISTS team_id;
ALTER TABLE public.dive_practice_announcements DROP COLUMN IF EXISTS team_id;
ALTER TABLE public.dive_practice_quotes        DROP COLUMN IF EXISTS team_id;
ALTER TABLE public.dive_practice_emphasis      DROP COLUMN IF EXISTS team_id;
ALTER TABLE public.dive_practice_notes         DROP COLUMN IF EXISTS team_id;
-- dive_practice_note_cards: table is unused by the app (Note Cards
-- feature was removed from the UI in an earlier session) — drop the
-- column for schema hygiene only, RLS left untouched below.
ALTER TABLE public.dive_practice_note_cards    DROP COLUMN IF EXISTS team_id;


-- =============================================
-- 2. PLANS: drop team_id, add groups + visibility
-- =============================================

ALTER TABLE public.dive_practice_plans DROP COLUMN IF EXISTS team_id;
ALTER TABLE public.dive_practice_plans
  ADD COLUMN IF NOT EXISTS groups TEXT[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS visibility TEXT NOT NULL DEFAULT 'club'
    CHECK (visibility IN ('club', 'private', 'superuser'));

CREATE INDEX IF NOT EXISTS idx_dive_practice_plans_visibility ON public.dive_practice_plans(visibility);


-- =============================================
-- 3. DROP TEAM / ROSTER TABLES (destructive, CASCADE)
-- =============================================

DROP TABLE IF EXISTS public.dive_practice_teams CASCADE;
DROP TABLE IF EXISTS public.dive_practice_players CASCADE;
DROP TABLE IF EXISTS public.dive_practice_player_groups CASCADE;
DROP TABLE IF EXISTS public.dive_practice_rosters CASCADE;
DROP TABLE IF EXISTS public.dive_practice_prefs CASCADE;


-- =============================================
-- 4. RECREATE PREFS (no active_team_id — one row per coach, still private)
-- =============================================

CREATE TABLE IF NOT EXISTS public.dive_practice_prefs (
  coach_id                UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  default_duration        TEXT,
  default_start_time      TEXT,
  time_format              TEXT DEFAULT '12',
  skill_edit_prompt       BOOLEAN DEFAULT false,
  include_images          BOOLEAN DEFAULT true,
  include_videos          BOOLEAN DEFAULT false,
  include_colors_print    BOOLEAN DEFAULT true,
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.dive_practice_prefs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dive_practice_prefs: coach full access" ON public.dive_practice_prefs;
CREATE POLICY "dive_practice_prefs: coach full access"
  ON public.dive_practice_prefs FOR ALL
  USING (coach_id = auth.uid());


-- =============================================
-- 5. NEW TABLE: dive_practice_groups (club-wide shared practice groups)
-- =============================================

CREATE TABLE IF NOT EXISTS public.dive_practice_groups (
  id          TEXT PRIMARY KEY,
  coach_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.dive_practice_groups ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_dive_practice_groups_coach_id ON public.dive_practice_groups(coach_id);


-- =============================================
-- 6. RLS: club-wide shared read / own write, applied to every shared table
-- =============================================
-- Pattern: any active coach can SELECT everything; only the creating
-- coach can INSERT (with their own coach_id)/UPDATE/DELETE their rows.

DO $$
DECLARE
  t TEXT;
  shared_tables TEXT[] := ARRAY[
    'dive_practice_categories',
    'dive_practice_skills',
    'dive_practice_skill_blocks',
    'dive_practice_locations',
    'dive_practice_announcements',
    'dive_practice_quotes',
    'dive_practice_emphasis',
    'dive_practice_notes',
    'dive_practice_groups'
  ];
BEGIN
  FOREACH t IN ARRAY shared_tables LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || ': coach full access', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || ': club read', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || ': own insert', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || ': own update', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || ': own delete', t);

    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR SELECT USING (
         EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = ''coach'' AND status = ''active'')
       )', t || ': club read', t
    );
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR INSERT WITH CHECK (coach_id = auth.uid())',
      t || ': own insert', t
    );
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR UPDATE USING (coach_id = auth.uid())',
      t || ': own update', t
    );
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR DELETE USING (coach_id = auth.uid())',
      t || ': own delete', t
    );
  END LOOP;
END $$;


-- =============================================
-- 7. RLS: dive_practice_plans (visibility-aware read, own write)
-- =============================================

DROP POLICY IF EXISTS "dive_practice_plans: coach full access" ON public.dive_practice_plans;
DROP POLICY IF EXISTS "dive_practice_plans: read" ON public.dive_practice_plans;
DROP POLICY IF EXISTS "dive_practice_plans: own insert" ON public.dive_practice_plans;
DROP POLICY IF EXISTS "dive_practice_plans: own update" ON public.dive_practice_plans;
DROP POLICY IF EXISTS "dive_practice_plans: own delete" ON public.dive_practice_plans;

CREATE POLICY "dive_practice_plans: read"
  ON public.dive_practice_plans FOR SELECT
  USING (
    coach_id = auth.uid()
    OR (
      visibility = 'club'
      AND EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'coach' AND status = 'active')
    )
    OR (
      visibility = 'superuser'
      AND EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_super_user = true)
    )
  );

CREATE POLICY "dive_practice_plans: own insert"
  ON public.dive_practice_plans FOR INSERT
  WITH CHECK (coach_id = auth.uid());

CREATE POLICY "dive_practice_plans: own update"
  ON public.dive_practice_plans FOR UPDATE
  USING (coach_id = auth.uid());

CREATE POLICY "dive_practice_plans: own delete"
  ON public.dive_practice_plans FOR DELETE
  USING (coach_id = auth.uid());
