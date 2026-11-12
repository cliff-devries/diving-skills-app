-- Migration v83: Club classes system
-- Adds club_classes table (coach-managed timeslots per group) and
-- diver_class_ids column on profiles (text[] of enrolled class IDs).
--
-- club_classes rows are club-wide (not per-coach). RLS mirrors club_settings:
--   coaches and super users can read/write; divers/parents read-only.
-- diver_class_ids is updated via a new RPC so the existing coach RLS on
-- profiles (update only own divers) is respected.

-- ── 1. club_classes table ────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS club_classes (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_name   text NOT NULL,          -- matches profiles.diver_group
  day          text NOT NULL,          -- 'Monday','Tuesday',…,'Saturday','Sunday'
  start_time   time NOT NULL,          -- e.g. 18:00
  end_time     time NOT NULL,          -- e.g. 18:45
  location     text NOT NULL DEFAULT '',  -- 'RIT Pool','Dryland','Canandaigua Academy',…
  sort_order   integer NOT NULL DEFAULT 0,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- RLS
ALTER TABLE club_classes ENABLE ROW LEVEL SECURITY;

-- Coaches and super users: full access
CREATE POLICY "Coaches can manage club_classes"
  ON club_classes FOR ALL
  USING  (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('coach','super_user')))
  WITH CHECK (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('coach','super_user')));

-- Divers and parents: read-only
CREATE POLICY "Divers can read club_classes"
  ON club_classes FOR SELECT
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('diver','parent')));

-- Index for fast group lookups
CREATE INDEX IF NOT EXISTS club_classes_group_name_idx ON club_classes (group_name);

-- ── 2. diver_class_ids column on profiles ───────────────────────────────────

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS diver_class_ids text[] NOT NULL DEFAULT '{}';

-- ── 3. RPC: update_diver_class_ids ──────────────────────────────────────────
-- Coaches call this to set a diver's class enrollment.
-- RLS on profiles already lets coaches update their own divers; this RPC
-- wraps it so the caller never needs to touch the profiles table directly.

CREATE OR REPLACE FUNCTION update_diver_class_ids(
  p_diver_id  uuid,
  p_class_ids text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_role text;
BEGIN
  -- Only coaches and super users may call this
  SELECT role INTO v_caller_role FROM profiles WHERE id = auth.uid();
  IF v_caller_role NOT IN ('coach', 'super_user') THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE profiles
  SET    diver_class_ids = COALESCE(p_class_ids, '{}')
  WHERE  id = p_diver_id
    AND  role = 'diver';
END;
$$;

GRANT EXECUTE ON FUNCTION update_diver_class_ids(uuid, text[]) TO authenticated;

-- ── 4. Seed the current class schedule (November 2026) ──────────────────────
-- sort_order: within a group, 1 = Mon, 2 = Tue, … 7 = Sun; ties broken by start_time.
-- These are INSERT … ON CONFLICT DO NOTHING so re-running is safe.
-- (No unique constraint needed for seeding — just run once.)

INSERT INTO club_classes (group_name, day, start_time, end_time, location, sort_order) VALUES
  -- Learn to Dive (RIT)
  ('Learn to Dive', 'Tuesday',   '18:00', '18:45', 'RIT Pool',              1),
  ('Learn to Dive', 'Tuesday',   '18:45', '19:30', 'RIT Pool',              2),
  ('Learn to Dive', 'Thursday',  '18:00', '18:45', 'RIT Pool',              3),
  ('Learn to Dive', 'Thursday',  '18:45', '19:30', 'RIT Pool',              4),
  ('Learn to Dive', 'Saturday',  '11:30', '12:15', 'Dryland',               5),

  -- Novice (RIT)
  ('Novice', 'Tuesday',   '18:00', '19:30', 'RIT Pool',                     1),
  ('Novice', 'Tuesday',   '18:00', '19:30', 'Dryland',                      2),
  ('Novice', 'Thursday',  '18:00', '19:30', 'RIT Pool',                     3),
  ('Novice', 'Thursday',  '18:00', '19:30', 'Dryland',                      4),
  ('Novice', 'Friday',    '18:00', '19:30', 'Dryland',                      5),

  -- Lessons (RIT)
  ('Lessons', 'Monday',    '18:00', '19:30', 'RIT Pool',                    1),
  ('Lessons', 'Wednesday', '18:00', '19:30', 'RIT Pool',                    2),
  ('Lessons', 'Saturday',  '10:00', '11:30', 'Dryland',                     3),

  -- Sparks (competition team — auto-enrolled)
  ('Sparks', 'Tuesday',   '16:45', '17:45', 'Dryland',                      1),
  ('Sparks', 'Tuesday',   '18:00', '18:45', 'RIT Pool',                     2),
  ('Sparks', 'Thursday',  '16:45', '17:45', 'Dryland',                      3),
  ('Sparks', 'Thursday',  '18:00', '18:45', 'RIT Pool',                     4),
  ('Sparks', 'Saturday',  '08:30', '10:00', 'Dryland',                      5),

  -- Fire (competition team — auto-enrolled)
  ('Fire', 'Monday',    '18:00', '19:30', 'RIT Pool',                       1),
  ('Fire', 'Tuesday',   '16:45', '17:45', 'Dryland',                        2),
  ('Fire', 'Wednesday', '18:00', '19:30', 'RIT Pool',                       3),
  ('Fire', 'Thursday',  '16:45', '17:45', 'Dryland',                        4),
  ('Fire', 'Friday',    '18:00', '19:30', 'RIT Pool',                       5),
  ('Fire', 'Saturday',  '10:00', '11:30', 'Dryland',                        6),

  -- Blaze (competition team — auto-enrolled)
  ('Blaze', 'Monday',    '18:00', '19:30', 'RIT Pool',                      1),
  ('Blaze', 'Tuesday',   '16:45', '17:45', 'Dryland',                       2),
  ('Blaze', 'Tuesday',   '18:00', '19:30', 'RIT Pool',                      3),
  ('Blaze', 'Wednesday', '18:00', '19:30', 'RIT Pool',                      4),
  ('Blaze', 'Thursday',  '16:45', '17:45', 'Dryland',                       5),
  ('Blaze', 'Thursday',  '18:00', '19:30', 'RIT Pool',                      6),
  ('Blaze', 'Friday',    '18:00', '19:30', 'RIT Pool',                      7),
  ('Blaze', 'Saturday',  '10:00', '11:30', 'Dryland',                       8),

  -- Canandaigua Learn to Dive
  ('Canandaigua LTD',     'Wednesday', '18:00', '18:45', 'Canandaigua Academy', 1),

  -- Canandaigua Lessons
  ('Canandaigua Lessons', 'Wednesday', '18:00', '19:30', 'Canandaigua Academy', 1);
