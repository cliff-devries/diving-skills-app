-- =============================================================
-- Migration v87 — DiveAttendance tables
-- att_groups, att_divers, att_records, att_sessions
-- RLS: coaches and super users only (reuses crm_is_coach()).
-- =============================================================

-- ---- Groups (practice groups / training squads) ----
CREATE TABLE IF NOT EXISTS public.att_groups (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  color       TEXT NOT NULL DEFAULT '#43A047',
  schedule    TEXT NOT NULL DEFAULT '',
  archived    BOOLEAN NOT NULL DEFAULT false,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.att_groups ENABLE ROW LEVEL SECURITY;

CREATE POLICY att_groups_select ON public.att_groups
  FOR SELECT TO authenticated USING (public.crm_is_coach());
CREATE POLICY att_groups_insert ON public.att_groups
  FOR INSERT TO authenticated WITH CHECK (public.crm_is_coach());
CREATE POLICY att_groups_update ON public.att_groups
  FOR UPDATE TO authenticated USING (public.crm_is_coach()) WITH CHECK (public.crm_is_coach());
CREATE POLICY att_groups_delete ON public.att_groups
  FOR DELETE TO authenticated USING (public.crm_is_coach());

-- ---- Divers (attendees, may link to a DiveDrills profile) ----
CREATE TABLE IF NOT EXISTS public.att_divers (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  group_ids   TEXT[] NOT NULL DEFAULT '{}',
  active      BOOLEAN NOT NULL DEFAULT true,
  ext_id      TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.att_divers ENABLE ROW LEVEL SECURITY;

CREATE POLICY att_divers_select ON public.att_divers
  FOR SELECT TO authenticated USING (public.crm_is_coach());
CREATE POLICY att_divers_insert ON public.att_divers
  FOR INSERT TO authenticated WITH CHECK (public.crm_is_coach());
CREATE POLICY att_divers_update ON public.att_divers
  FOR UPDATE TO authenticated USING (public.crm_is_coach()) WITH CHECK (public.crm_is_coach());
CREATE POLICY att_divers_delete ON public.att_divers
  FOR DELETE TO authenticated USING (public.crm_is_coach());

-- ---- Records (per-diver per-session attendance mark) ----
CREATE TABLE IF NOT EXISTS public.att_records (
  id          TEXT PRIMARY KEY,
  date        TEXT NOT NULL,
  group_id    TEXT NOT NULL,
  diver_id    TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT '',
  note        TEXT NOT NULL DEFAULT '',
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.att_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY att_records_select ON public.att_records
  FOR SELECT TO authenticated USING (public.crm_is_coach());
CREATE POLICY att_records_insert ON public.att_records
  FOR INSERT TO authenticated WITH CHECK (public.crm_is_coach());
CREATE POLICY att_records_update ON public.att_records
  FOR UPDATE TO authenticated USING (public.crm_is_coach()) WITH CHECK (public.crm_is_coach());
CREATE POLICY att_records_delete ON public.att_records
  FOR DELETE TO authenticated USING (public.crm_is_coach());

-- ---- Sessions (per-group per-date session note) ----
CREATE TABLE IF NOT EXISTS public.att_sessions (
  id          TEXT PRIMARY KEY,   -- format: "YYYY-MM-DD|group_id"
  date        TEXT NOT NULL,
  group_id    TEXT NOT NULL,
  note        TEXT NOT NULL DEFAULT '',
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.att_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY att_sessions_select ON public.att_sessions
  FOR SELECT TO authenticated USING (public.crm_is_coach());
CREATE POLICY att_sessions_insert ON public.att_sessions
  FOR INSERT TO authenticated WITH CHECK (public.crm_is_coach());
CREATE POLICY att_sessions_update ON public.att_sessions
  FOR UPDATE TO authenticated USING (public.crm_is_coach()) WITH CHECK (public.crm_is_coach());
CREATE POLICY att_sessions_delete ON public.att_sessions
  FOR DELETE TO authenticated USING (public.crm_is_coach());

-- Speed up common attendance queries
CREATE INDEX IF NOT EXISTS att_records_date_group ON public.att_records (date, group_id);
CREATE INDEX IF NOT EXISTS att_records_diver      ON public.att_records (diver_id);
CREATE INDEX IF NOT EXISTS att_records_updated    ON public.att_records (updated_at);
CREATE INDEX IF NOT EXISTS att_groups_updated     ON public.att_groups  (updated_at);
CREATE INDEX IF NOT EXISTS att_divers_updated     ON public.att_divers  (updated_at);
CREATE INDEX IF NOT EXISTS att_sessions_updated   ON public.att_sessions (updated_at);
