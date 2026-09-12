-- ============================================================
-- Migration v52 — Public (anonymous) read access for the standalone
-- leaderboard-public.html page. Run once in the Supabase SQL editor.
-- Safe to re-run (CREATE OR REPLACE / idempotent grants).
--
-- SECURITY NOTE — this deliberately does NOT add the RLS policies
-- originally proposed for this feature:
--
--   CREATE POLICY "leaderboard_scores: public read" ... USING (true);
--   CREATE POLICY "profiles: public read diver names" ...
--     USING (role = 'diver' AND status = 'active');
--
-- A `USING (...)` clause on a SELECT policy filters ROWS, not COLUMNS.
-- Granting anon a SELECT policy on profiles — even one scoped to
-- "role = 'diver' AND status = 'active'" — would let anyone holding the
-- anon key (which is public by design; see netlify.toml) run
--   select('*').eq('role','diver').eq('status','active')
-- directly against PostgREST and pull EVERY column for EVERY active
-- diver: email, date_of_birth, phone, parent_email, parent_phone, notes
-- (see supabase-migration-v3.sql / v21.sql) — full contact info and
-- birthdates for minors, permanently public the moment this ships.
-- Same problem on leaderboard_scores with `USING (true)`: it would also
-- expose notes and recorded_by (an internal coach reference), and hand
-- out every diver_id, letting anyone rejoin scores to full profiles.
--
-- This app already has an established, safer pattern for exactly this
-- situation — public sharing of practice plans (migration v50): a single
-- SECURITY DEFINER function that returns only the specific narrow columns
-- a public page needs, with EXECUTE granted to anon and NO new SELECT
-- policy on the underlying table at all. Same approach here: one RPC,
-- get_public_leaderboard(), joins leaderboard_scores to profiles
-- internally (bypassing RLS as the function owner) and returns only
-- exercise/score/score_type/recorded_at plus first name, a single last-
-- initial character (never the full last name), aqua_group, and gender.
-- diver_id, email, date_of_birth, phone, parent_email, parent_phone,
-- notes, and recorded_by are never returned. Rows with a non-numeric
-- aqua_group (e.g. the 'TBD' default for a diver with no DOB on file —
-- see supabase-migration-v21.sql) are excluded, since there's no
-- meaningful public age group for them.
-- ============================================================

DROP FUNCTION IF EXISTS public.get_public_leaderboard();

CREATE OR REPLACE FUNCTION public.get_public_leaderboard()
RETURNS TABLE (
  exercise      TEXT,
  score         NUMERIC,
  score_type    TEXT,
  recorded_at   TIMESTAMPTZ,
  first_name    TEXT,
  last_initial  TEXT,
  aqua_group    TEXT,
  gender        TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ls.exercise,
    ls.score,
    ls.score_type,
    ls.recorded_at,
    COALESCE(
      NULLIF(TRIM(p.first_name), ''),
      SPLIT_PART(TRIM(COALESCE(p.full_name, '')), ' ', 1),
      ''
    ) AS first_name,
    COALESCE(
      LEFT(NULLIF(TRIM(p.last_name), ''), 1),
      CASE
        WHEN POSITION(' ' IN TRIM(COALESCE(p.full_name, ''))) > 0
          THEN LEFT(TRIM(SUBSTRING(TRIM(p.full_name) FROM POSITION(' ' IN TRIM(p.full_name)) + 1)), 1)
        ELSE NULL
      END,
      ''
    ) AS last_initial,
    p.aqua_group,
    p.gender
  FROM public.leaderboard_scores ls
  JOIN public.profiles p ON p.id = ls.diver_id
  WHERE p.role = 'diver'
    AND p.status = 'active'
    AND p.aqua_group ~ '^[0-9]+$';
END;
$$;

REVOKE ALL ON FUNCTION public.get_public_leaderboard() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_leaderboard() TO anon;
GRANT EXECUTE ON FUNCTION public.get_public_leaderboard() TO authenticated;
