-- =============================================
-- DIVING SKILLS — Supabase Database Setup
-- Run this in the Supabase SQL Editor:
--   supabase.com → your project → SQL Editor → New Query
-- Safe to re-run: tables use IF NOT EXISTS, policies use DROP IF EXISTS.
-- =============================================


-- =============================================
-- 1. CREATE TABLES (all before any policies)
-- =============================================

CREATE TABLE IF NOT EXISTS public.profiles (
  id           UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email        TEXT NOT NULL,
  full_name    TEXT NOT NULL DEFAULT '',
  role         TEXT NOT NULL DEFAULT 'diver'
                 CHECK (role IN ('coach', 'diver', 'parent')),
  coach_id     UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  avatar_url   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.roster (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coach_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  diver_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  joined_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (coach_id, diver_id)
);

CREATE TABLE IF NOT EXISTS public.parent_diver (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id  UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  diver_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  UNIQUE (parent_id, diver_id)
);

-- Skills library — managed by coaches, read by everyone.
-- requires_harness marks skills denoted with "+" in the curriculum.
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

CREATE TABLE IF NOT EXISTS public.skill_completions (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  diver_id            UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  skill_id            INTEGER NOT NULL REFERENCES public.skills(id) ON DELETE CASCADE,
  self_reported_at    TIMESTAMPTZ,
  coach_confirmed_at  TIMESTAMPTZ,
  coach_id            UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  notes               TEXT DEFAULT '',
  UNIQUE (diver_id, skill_id)
);


-- =============================================
-- 2. ENABLE ROW LEVEL SECURITY
-- =============================================

ALTER TABLE public.profiles          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roster            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parent_diver      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.skills            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.skill_completions ENABLE ROW LEVEL SECURITY;


-- =============================================
-- 3. PROFILES POLICIES
-- =============================================

DROP POLICY IF EXISTS "profiles: own read"                      ON public.profiles;
DROP POLICY IF EXISTS "profiles: own insert"                    ON public.profiles;
DROP POLICY IF EXISTS "profiles: own update"                    ON public.profiles;
DROP POLICY IF EXISTS "profiles: coach reads roster divers"     ON public.profiles;
DROP POLICY IF EXISTS "profiles: parent reads linked divers"    ON public.profiles;
DROP POLICY IF EXISTS "profiles: authenticated lookup by email" ON public.profiles;

CREATE POLICY "profiles: own read"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "profiles: own insert"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles: own update"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

CREATE POLICY "profiles: coach reads roster divers"
  ON public.profiles FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = profiles.id
    )
  );

CREATE POLICY "profiles: parent reads linked divers"
  ON public.profiles FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.parent_diver
      WHERE parent_diver.parent_id = auth.uid()
        AND parent_diver.diver_id  = profiles.id
    )
  );

-- Coaches need this to add divers to roster by email lookup
CREATE POLICY "profiles: authenticated lookup by email"
  ON public.profiles FOR SELECT
  USING (auth.role() = 'authenticated' AND role = 'diver');


-- =============================================
-- 4. ROSTER POLICIES
-- =============================================

DROP POLICY IF EXISTS "roster: coach full access" ON public.roster;
DROP POLICY IF EXISTS "roster: diver read own"    ON public.roster;

CREATE POLICY "roster: coach full access"
  ON public.roster FOR ALL
  USING (auth.uid() = coach_id);

CREATE POLICY "roster: diver read own"
  ON public.roster FOR SELECT
  USING (auth.uid() = diver_id);


-- =============================================
-- 5. PARENT_DIVER POLICIES
-- =============================================

DROP POLICY IF EXISTS "parent_diver: parent read own"            ON public.parent_diver;
DROP POLICY IF EXISTS "parent_diver: coach manages their divers" ON public.parent_diver;

CREATE POLICY "parent_diver: parent read own"
  ON public.parent_diver FOR SELECT
  USING (auth.uid() = parent_id);

CREATE POLICY "parent_diver: coach manages their divers"
  ON public.parent_diver FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = parent_diver.diver_id
    )
  );


-- =============================================
-- 6. SKILLS POLICIES
-- All authenticated users read; coaches write.
-- =============================================

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


-- =============================================
-- 7. SKILL_COMPLETIONS POLICIES
-- =============================================

DROP POLICY IF EXISTS "skill_completions: diver read own"            ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: diver insert"              ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: diver update own"          ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: coach manages roster"      ON public.skill_completions;
DROP POLICY IF EXISTS "skill_completions: parent reads linked diver" ON public.skill_completions;

CREATE POLICY "skill_completions: diver read own"
  ON public.skill_completions FOR SELECT
  USING (auth.uid() = diver_id);

CREATE POLICY "skill_completions: diver insert"
  ON public.skill_completions FOR INSERT
  WITH CHECK (auth.uid() = diver_id);

CREATE POLICY "skill_completions: diver update own"
  ON public.skill_completions FOR UPDATE
  USING (auth.uid() = diver_id);

CREATE POLICY "skill_completions: coach manages roster"
  ON public.skill_completions FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = skill_completions.diver_id
    )
  );

CREATE POLICY "skill_completions: parent reads linked diver"
  ON public.skill_completions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.parent_diver
      WHERE parent_diver.parent_id = auth.uid()
        AND parent_diver.diver_id  = skill_completions.diver_id
    )
  );


-- =============================================
-- 8. TRIGGERS
-- =============================================

-- Auto-create profile row when a new auth user signs up.
-- Pass options.data in signUp(): { full_name: 'Jane Smith', role: 'diver' }
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'role', 'diver')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Auto-update skills.updated_at on every UPDATE.
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


-- =============================================
-- 9. INDEXES
-- =============================================

CREATE INDEX IF NOT EXISTS idx_roster_coach_id         ON public.roster(coach_id);
CREATE INDEX IF NOT EXISTS idx_roster_diver_id         ON public.roster(diver_id);
CREATE INDEX IF NOT EXISTS idx_parent_diver_parent_id  ON public.parent_diver(parent_id);
CREATE INDEX IF NOT EXISTS idx_skills_level            ON public.skills(skill_level);
CREATE INDEX IF NOT EXISTS idx_skills_type             ON public.skills(skill_type);
CREATE INDEX IF NOT EXISTS idx_completions_diver_id    ON public.skill_completions(diver_id);
CREATE INDEX IF NOT EXISTS idx_completions_skill_id    ON public.skill_completions(skill_id);
CREATE INDEX IF NOT EXISTS idx_profiles_email          ON public.profiles(email);
CREATE INDEX IF NOT EXISTS idx_profiles_role           ON public.profiles(role);
