-- =============================================
-- DIVING SKILLS — Migration v41: DivePractice cloud storage
-- Run this ONCE in the Supabase SQL Editor on an existing database.
--
-- Background: practice.html (DivePractice) has been 100% localStorage-backed
-- until now, so a coach's practice plans, skill library, rosters, etc. were
-- trapped on one browser/device. This migration adds Supabase tables so the
-- app can sync to the cloud while keeping localStorage as an offline
-- fallback (see practice.html's new loadDB()/saveDB()/runSync()).
--
-- Schema notes:
--   - Every id is TEXT PRIMARY KEY, matching the app's own uid() scheme
--     (e.g. "skill_1005_a1b2c") — NOT uuid. Converting to uuid would break
--     every existing cross-reference by id string throughout the app and
--     in every already-exported backup JSON file.
--   - Every per-team table has team_id REFERENCES dive_practice_teams(id)
--     ON DELETE CASCADE, so deleting a team cascades all its data — the
--     app's sync engine never has to individually clean up a deleted
--     team's children.
--   - dive_practice_emphasis holds BOTH "practice emphasis" and
--     "competition emphasis" entries (two separate lists in the app),
--     distinguished by a `kind` column, instead of two near-identical
--     tables.
--   - dive_practice_players / _rosters / _player_groups / _notes are real,
--     fully-implemented entity types in the app (players, rosters, player
--     groups, and a free-standing "notes" list separate from note cards).
--   - dive_practice_teams has no "active" flag — the single active team is
--     coach-level state (dive_practice_prefs.active_team_id), not a
--     per-team property, so there's nothing to keep in sync.
--   - Images (skill.image, plan row .image, team.logo) are stored as
--     plain base64 data-URL TEXT for this pass, matching how the app
--     already stores them in localStorage — no new upload flow. A future
--     move to Supabase Storage is a reasonable follow-up, not done here.
--
-- RLS: every table uses the same single-policy pattern as the existing
-- "roster: coach full access" policy (supabase-setup.sql) — a direct
-- coach_id = auth.uid() check, no joins. This is a coach's own private
-- data with no cross-coach or cross-role reader in MVP scope (sharing
-- plans between coaches is an explicit Phase 2 item).
-- =============================================


-- =============================================
-- 1. TEAMS
-- =============================================

CREATE TABLE IF NOT EXISTS public.dive_practice_teams (
  id               TEXT PRIMARY KEY,
  coach_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name             TEXT NOT NULL,
  logo             TEXT,
  primary_color    TEXT DEFAULT '#00c9a7',
  secondary_color  TEXT DEFAULT '#0086E6',
  season_end_date  TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.dive_practice_teams ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dive_practice_teams: coach full access" ON public.dive_practice_teams;
CREATE POLICY "dive_practice_teams: coach full access"
  ON public.dive_practice_teams FOR ALL
  USING (coach_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_dp_teams_coach_id ON public.dive_practice_teams(coach_id);


-- =============================================
-- 2. COACH PREFERENCES (one row per coach)
-- =============================================

CREATE TABLE IF NOT EXISTS public.dive_practice_prefs (
  coach_id                UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  active_team_id          TEXT REFERENCES public.dive_practice_teams(id) ON DELETE SET NULL,
  default_duration        TEXT,
  default_start_time      TEXT,
  time_format             TEXT DEFAULT '12',
  skill_edit_prompt       BOOLEAN DEFAULT false,
  include_images          BOOLEAN DEFAULT true,
  include_videos          BOOLEAN DEFAULT false,
  notecards_in_printout   BOOLEAN DEFAULT true,
  include_colors_print    BOOLEAN DEFAULT true,
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.dive_practice_prefs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dive_practice_prefs: coach full access" ON public.dive_practice_prefs;
CREATE POLICY "dive_practice_prefs: coach full access"
  ON public.dive_practice_prefs FOR ALL
  USING (coach_id = auth.uid());


-- =============================================
-- 3. PER-TEAM ENTITY TABLES
-- =============================================

CREATE TABLE IF NOT EXISTS public.dive_practice_categories (
  id          TEXT PRIMARY KEY,
  coach_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  team_id     TEXT NOT NULL REFERENCES public.dive_practice_teams(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'Enabled',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.dive_practice_categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dive_practice_categories: coach full access" ON public.dive_practice_categories;
CREATE POLICY "dive_practice_categories: coach full access"
  ON public.dive_practice_categories FOR ALL
  USING (coach_id = auth.uid());
CREATE INDEX IF NOT EXISTS idx_dive_practice_categories_coach_id ON public.dive_practice_categories(coach_id);
CREATE INDEX IF NOT EXISTS idx_dive_practice_categories_team_id  ON public.dive_practice_categories(team_id);

CREATE TABLE IF NOT EXISTS public.dive_practice_skills (
  id           TEXT PRIMARY KEY,
  coach_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  team_id      TEXT NOT NULL REFERENCES public.dive_practice_teams(id) ON DELETE CASCADE,
  category_id  TEXT,
  name         TEXT NOT NULL,
  minutes      INTEGER DEFAULT 5,
  notes        TEXT,
  stations     BOOLEAN DEFAULT false,
  status       TEXT NOT NULL DEFAULT 'Enabled',
  image        TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.dive_practice_skills ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dive_practice_skills: coach full access" ON public.dive_practice_skills;
CREATE POLICY "dive_practice_skills: coach full access"
  ON public.dive_practice_skills FOR ALL
  USING (coach_id = auth.uid());
CREATE INDEX IF NOT EXISTS idx_dive_practice_skills_coach_id ON public.dive_practice_skills(coach_id);
CREATE INDEX IF NOT EXISTS idx_dive_practice_skills_team_id  ON public.dive_practice_skills(team_id);

CREATE TABLE IF NOT EXISTS public.dive_practice_skill_blocks (
  id          TEXT PRIMARY KEY,
  coach_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  team_id     TEXT NOT NULL REFERENCES public.dive_practice_teams(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  skill_ids   TEXT[] NOT NULL DEFAULT '{}',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.dive_practice_skill_blocks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dive_practice_skill_blocks: coach full access" ON public.dive_practice_skill_blocks;
CREATE POLICY "dive_practice_skill_blocks: coach full access"
  ON public.dive_practice_skill_blocks FOR ALL
  USING (coach_id = auth.uid());
CREATE INDEX IF NOT EXISTS idx_dive_practice_skill_blocks_coach_id ON public.dive_practice_skill_blocks(coach_id);
CREATE INDEX IF NOT EXISTS idx_dive_practice_skill_blocks_team_id  ON public.dive_practice_skill_blocks(team_id);

CREATE TABLE IF NOT EXISTS public.dive_practice_locations (
  id          TEXT PRIMARY KEY,
  coach_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  team_id     TEXT NOT NULL REFERENCES public.dive_practice_teams(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.dive_practice_locations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dive_practice_locations: coach full access" ON public.dive_practice_locations;
CREATE POLICY "dive_practice_locations: coach full access"
  ON public.dive_practice_locations FOR ALL
  USING (coach_id = auth.uid());
CREATE INDEX IF NOT EXISTS idx_dive_practice_locations_coach_id ON public.dive_practice_locations(coach_id);
CREATE INDEX IF NOT EXISTS idx_dive_practice_locations_team_id  ON public.dive_practice_locations(team_id);

CREATE TABLE IF NOT EXISTS public.dive_practice_announcements (
  id          TEXT PRIMARY KEY,
  coach_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  team_id     TEXT NOT NULL REFERENCES public.dive_practice_teams(id) ON DELETE CASCADE,
  text        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.dive_practice_announcements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dive_practice_announcements: coach full access" ON public.dive_practice_announcements;
CREATE POLICY "dive_practice_announcements: coach full access"
  ON public.dive_practice_announcements FOR ALL
  USING (coach_id = auth.uid());
CREATE INDEX IF NOT EXISTS idx_dive_practice_announcements_coach_id ON public.dive_practice_announcements(coach_id);
CREATE INDEX IF NOT EXISTS idx_dive_practice_announcements_team_id  ON public.dive_practice_announcements(team_id);

CREATE TABLE IF NOT EXISTS public.dive_practice_quotes (
  id          TEXT PRIMARY KEY,
  coach_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  team_id     TEXT NOT NULL REFERENCES public.dive_practice_teams(id) ON DELETE CASCADE,
  text        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.dive_practice_quotes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dive_practice_quotes: coach full access" ON public.dive_practice_quotes;
CREATE POLICY "dive_practice_quotes: coach full access"
  ON public.dive_practice_quotes FOR ALL
  USING (coach_id = auth.uid());
CREATE INDEX IF NOT EXISTS idx_dive_practice_quotes_coach_id ON public.dive_practice_quotes(coach_id);
CREATE INDEX IF NOT EXISTS idx_dive_practice_quotes_team_id  ON public.dive_practice_quotes(team_id);

-- Holds both "practice emphasis" and "competition emphasis" entries.
CREATE TABLE IF NOT EXISTS public.dive_practice_emphasis (
  id          TEXT PRIMARY KEY,
  coach_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  team_id     TEXT NOT NULL REFERENCES public.dive_practice_teams(id) ON DELETE CASCADE,
  kind        TEXT NOT NULL CHECK (kind IN ('practice', 'competition')),
  text        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.dive_practice_emphasis ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dive_practice_emphasis: coach full access" ON public.dive_practice_emphasis;
CREATE POLICY "dive_practice_emphasis: coach full access"
  ON public.dive_practice_emphasis FOR ALL
  USING (coach_id = auth.uid());
CREATE INDEX IF NOT EXISTS idx_dive_practice_emphasis_coach_id ON public.dive_practice_emphasis(coach_id);
CREATE INDEX IF NOT EXISTS idx_dive_practice_emphasis_team_id  ON public.dive_practice_emphasis(team_id);

CREATE TABLE IF NOT EXISTS public.dive_practice_notes (
  id          TEXT PRIMARY KEY,
  coach_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  team_id     TEXT NOT NULL REFERENCES public.dive_practice_teams(id) ON DELETE CASCADE,
  text        TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'Enabled',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.dive_practice_notes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dive_practice_notes: coach full access" ON public.dive_practice_notes;
CREATE POLICY "dive_practice_notes: coach full access"
  ON public.dive_practice_notes FOR ALL
  USING (coach_id = auth.uid());
CREATE INDEX IF NOT EXISTS idx_dive_practice_notes_coach_id ON public.dive_practice_notes(coach_id);
CREATE INDEX IF NOT EXISTS idx_dive_practice_notes_team_id  ON public.dive_practice_notes(team_id);

CREATE TABLE IF NOT EXISTS public.dive_practice_note_cards (
  id          TEXT PRIMARY KEY,
  coach_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  team_id     TEXT NOT NULL REFERENCES public.dive_practice_teams(id) ON DELETE CASCADE,
  title       TEXT NOT NULL,
  content     TEXT,
  status      TEXT NOT NULL DEFAULT 'Enabled',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.dive_practice_note_cards ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dive_practice_note_cards: coach full access" ON public.dive_practice_note_cards;
CREATE POLICY "dive_practice_note_cards: coach full access"
  ON public.dive_practice_note_cards FOR ALL
  USING (coach_id = auth.uid());
CREATE INDEX IF NOT EXISTS idx_dive_practice_note_cards_coach_id ON public.dive_practice_note_cards(coach_id);
CREATE INDEX IF NOT EXISTS idx_dive_practice_note_cards_team_id  ON public.dive_practice_note_cards(team_id);

CREATE TABLE IF NOT EXISTS public.dive_practice_player_groups (
  id                 TEXT PRIMARY KEY,
  coach_id           UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  team_id            TEXT NOT NULL REFERENCES public.dive_practice_teams(id) ON DELETE CASCADE,
  name               TEXT NOT NULL,
  num_groups         INTEGER,
  players_per_group  INTEGER,
  subs_per_group     INTEGER,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.dive_practice_player_groups ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dive_practice_player_groups: coach full access" ON public.dive_practice_player_groups;
CREATE POLICY "dive_practice_player_groups: coach full access"
  ON public.dive_practice_player_groups FOR ALL
  USING (coach_id = auth.uid());
CREATE INDEX IF NOT EXISTS idx_dive_practice_player_groups_coach_id ON public.dive_practice_player_groups(coach_id);
CREATE INDEX IF NOT EXISTS idx_dive_practice_player_groups_team_id  ON public.dive_practice_player_groups(team_id);

CREATE TABLE IF NOT EXISTS public.dive_practice_players (
  id          TEXT PRIMARY KEY,
  coach_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  team_id     TEXT NOT NULL REFERENCES public.dive_practice_teams(id) ON DELETE CASCADE,
  jersey      TEXT,
  first_name  TEXT NOT NULL,
  last_name   TEXT,
  email       TEXT,
  position    TEXT,
  grade       TEXT,
  status      TEXT NOT NULL DEFAULT 'Active',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.dive_practice_players ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dive_practice_players: coach full access" ON public.dive_practice_players;
CREATE POLICY "dive_practice_players: coach full access"
  ON public.dive_practice_players FOR ALL
  USING (coach_id = auth.uid());
CREATE INDEX IF NOT EXISTS idx_dive_practice_players_coach_id ON public.dive_practice_players(coach_id);
CREATE INDEX IF NOT EXISTS idx_dive_practice_players_team_id  ON public.dive_practice_players(team_id);

CREATE TABLE IF NOT EXISTS public.dive_practice_rosters (
  id          TEXT PRIMARY KEY,
  coach_id    UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  team_id     TEXT NOT NULL REFERENCES public.dive_practice_teams(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  player_ids  TEXT[] NOT NULL DEFAULT '{}',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.dive_practice_rosters ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dive_practice_rosters: coach full access" ON public.dive_practice_rosters;
CREATE POLICY "dive_practice_rosters: coach full access"
  ON public.dive_practice_rosters FOR ALL
  USING (coach_id = auth.uid());
CREATE INDEX IF NOT EXISTS idx_dive_practice_rosters_coach_id ON public.dive_practice_rosters(coach_id);
CREATE INDEX IF NOT EXISTS idx_dive_practice_rosters_team_id  ON public.dive_practice_rosters(team_id);

CREATE TABLE IF NOT EXISTS public.dive_practice_plans (
  id                    TEXT PRIMARY KEY,
  coach_id              UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  team_id               TEXT NOT NULL REFERENCES public.dive_practice_teams(id) ON DELETE CASCADE,
  name                  TEXT NOT NULL,
  date                  TEXT,
  location              TEXT,
  start_time            TEXT,
  ampm                  TEXT,
  duration              INTEGER DEFAULT 60,
  color                 TEXT DEFAULT '#00c9a7',
  announcements         TEXT,
  quote                 TEXT,
  practice_emphasis     TEXT,
  competition_emphasis  TEXT,
  filter_category       TEXT,
  note_card_ids         TEXT[] NOT NULL DEFAULT '{}',
  rows                  JSONB NOT NULL DEFAULT '[]',
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.dive_practice_plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dive_practice_plans: coach full access" ON public.dive_practice_plans;
CREATE POLICY "dive_practice_plans: coach full access"
  ON public.dive_practice_plans FOR ALL
  USING (coach_id = auth.uid());
CREATE INDEX IF NOT EXISTS idx_dive_practice_plans_coach_id ON public.dive_practice_plans(coach_id);
CREATE INDEX IF NOT EXISTS idx_dive_practice_plans_team_id  ON public.dive_practice_plans(team_id);
