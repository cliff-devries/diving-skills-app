-- ============================================================
-- Migration v27 — Expand update_diver_profile_by_coach to all coaches
-- Run once in Supabase SQL editor.
-- Requires v26-fix to be applied first (needs is_active_coach() function).
--
-- WHAT CHANGES:
--   update_diver_profile_by_coach:
--     - Adds first_name, last_name, date_of_birth params (previously
--       super-user-only via direct updateProfile call)
--     - Replaces roster membership check with is_active_coach() so any
--       active coach can edit any diver (matches v24 any-coach policy)
--     - full_name is updated automatically by trg_sync_profile_name (v10)
-- ============================================================

-- Drop old 8-param signature before recreating with 11 params.
DROP FUNCTION IF EXISTS public.update_diver_profile_by_coach(
  uuid, integer, text, text, date, text, text, text
);

CREATE OR REPLACE FUNCTION public.update_diver_profile_by_coach(
  p_diver_id            uuid,
  p_first_name          text,
  p_last_name           text,
  p_date_of_birth       date,
  p_current_level       integer,
  p_diver_group         text,
  p_assigned_coach_name text,
  p_start_date          date,
  p_parent_email        text,
  p_parent_phone        text,
  p_aqua_group          text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_active_coach() THEN
    RAISE EXCEPTION 'Only active coaches can update diver profiles';
  END IF;

  UPDATE public.profiles
  SET
    first_name            = NULLIF(TRIM(COALESCE(p_first_name, '')), ''),
    last_name             = NULLIF(TRIM(COALESCE(p_last_name, '')), ''),
    date_of_birth         = p_date_of_birth,
    current_level         = p_current_level,
    diver_group           = p_diver_group,
    assigned_coach_name   = p_assigned_coach_name,
    start_date            = p_start_date,
    parent_email          = p_parent_email,
    parent_phone          = p_parent_phone,
    aqua_group            = COALESCE(p_aqua_group, 'TBD')
  WHERE id = p_diver_id
    AND role = 'diver';
  -- full_name is kept in sync automatically by trg_sync_profile_name (migration v10)
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_diver_profile_by_coach TO authenticated;
