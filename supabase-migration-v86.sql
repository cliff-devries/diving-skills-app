-- ============================================================
-- Migration v86 — DiveSignUp: parent sign-up app tables
-- Run once in the Supabase SQL editor. Safe to re-run.
--
-- Three tables:
--   su_activities  — events the organizer creates
--   su_items       — things parents can sign up for (belong to an activity)
--   su_signups     — a parent's commitment to bring/do an item
--
-- Access model:
--   - Public (anon) may SELECT all three tables (read-only).
--   - All writes (INSERT/UPDATE/DELETE) go through the Netlify su-api
--     function, which runs as service_role and validates the organizer
--     password server-side.  Anon has no write access at all.
-- ============================================================

-- ── Activities ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.su_activities (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title       TEXT NOT NULL CHECK (char_length(trim(title)) > 0),
  date        DATE,
  time_text   TEXT,
  location    TEXT,
  notes       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Items ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.su_items (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id  UUID NOT NULL REFERENCES public.su_activities(id) ON DELETE CASCADE,
  name         TEXT NOT NULL CHECK (char_length(trim(name)) > 0),
  description  TEXT,
  spots_needed INTEGER NOT NULL DEFAULT 1 CHECK (spots_needed >= 1),
  sort_order   INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS su_items_activity_idx ON public.su_items (activity_id);

-- ── Signups ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.su_signups (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_id  UUID NOT NULL REFERENCES public.su_activities(id) ON DELETE CASCADE,
  item_id      UUID NOT NULL REFERENCES public.su_items(id) ON DELETE CASCADE,
  name         TEXT NOT NULL CHECK (char_length(trim(name)) > 0),
  email        TEXT,
  qty          INTEGER NOT NULL DEFAULT 1 CHECK (qty >= 1),
  note         TEXT,
  edit_token   UUID NOT NULL DEFAULT gen_random_uuid(),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS su_signups_item_idx     ON public.su_signups (item_id);
CREATE INDEX IF NOT EXISTS su_signups_activity_idx ON public.su_signups (activity_id);
CREATE UNIQUE INDEX IF NOT EXISTS su_signups_token_idx ON public.su_signups (edit_token);

-- ── RLS ──────────────────────────────────────────────────────
ALTER TABLE public.su_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.su_items      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.su_signups    ENABLE ROW LEVEL SECURITY;

-- Public read
DROP POLICY IF EXISTS su_activities_public_read ON public.su_activities;
CREATE POLICY su_activities_public_read ON public.su_activities FOR SELECT USING (true);

DROP POLICY IF EXISTS su_items_public_read ON public.su_items;
CREATE POLICY su_items_public_read ON public.su_items FOR SELECT USING (true);

DROP POLICY IF EXISTS su_signups_public_read ON public.su_signups;
CREATE POLICY su_signups_public_read ON public.su_signups FOR SELECT USING (true);

-- No anon writes — all mutations go through su-api (service_role bypasses RLS)
