-- ============================================================
-- Migration v21 — New diver profile fields
-- Run once in Supabase SQL editor.
-- ============================================================

-- New columns on profiles table
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS diver_group           text,
  ADD COLUMN IF NOT EXISTS start_date            date,
  ADD COLUMN IF NOT EXISTS assigned_coach_name   text,
  ADD COLUMN IF NOT EXISTS aqua_group            text DEFAULT 'TBD',
  ADD COLUMN IF NOT EXISTS parent_email          text,
  ADD COLUMN IF NOT EXISTS parent_phone          text;

-- RPC: coach updates diver profile fields they're allowed to edit.
-- SECURITY DEFINER bypasses RLS — verifies roster membership first.
CREATE OR REPLACE FUNCTION public.update_diver_profile_by_coach(
  p_diver_id            uuid,
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
DECLARE
  v_caller_id uuid := auth.uid();
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.roster
    WHERE coach_id = v_caller_id AND diver_id = p_diver_id
  ) THEN
    RAISE EXCEPTION 'Not authorized: diver is not on your roster';
  END IF;

  UPDATE public.profiles
  SET
    current_level         = p_current_level,
    diver_group           = p_diver_group,
    assigned_coach_name   = p_assigned_coach_name,
    start_date            = p_start_date,
    parent_email          = p_parent_email,
    parent_phone          = p_parent_phone,
    aqua_group            = COALESCE(p_aqua_group, 'TBD')
  WHERE id = p_diver_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_diver_profile_by_coach TO authenticated;
