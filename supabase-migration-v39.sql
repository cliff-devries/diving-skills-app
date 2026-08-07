-- =============================================
-- DIVING SKILLS — Migration v39: Auto-assign coach name on diver creation
-- Run this ONCE in the Supabase SQL Editor on an existing database.
--
-- What this does:
--   Updates create_unclaimed_diver (last defined in v11) so a new diver's
--   assigned_coach_name is set to the creating coach's own full_name at
--   creation time, instead of being left NULL until a coach manually
--   fills it in via Edit Diver Profile.
--
--   Implemented server-side (looked up from the coach's own profiles row,
--   the same row already used to authorize the call) rather than as a
--   client-supplied parameter — same value either way since currentUser
--   on the client is sourced from that same row, but this way it can't
--   go stale or be spoofed, and the RPC's parameter list doesn't need to
--   change. Roster cards and profile pages already fall back to the
--   logged-in coach's name / roster-linked coach when this field is
--   NULL, but leaving the column unset meant that fallback was the only
--   place the name showed correctly — e.g. PDF reports (js/reports.js)
--   read assigned_coach_name directly with no fallback.
--
--   Function signature is unchanged from v11, so CREATE OR REPLACE is
--   safe without a DROP FUNCTION first.
-- =============================================

CREATE OR REPLACE FUNCTION public.create_unclaimed_diver(
  p_first_name         TEXT,
  p_last_name          TEXT,
  p_email              TEXT,
  p_date_of_birth      DATE,
  p_current_level      INTEGER,
  p_phone              TEXT,
  p_parent_guardian    TEXT,
  p_notes              TEXT,
  p_gender             TEXT
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_coach_id   UUID;
  v_coach_name TEXT;
  v_profile_id UUID;
BEGIN
  -- Caller must be an authenticated coach
  SELECT id, full_name INTO v_coach_id, v_coach_name
  FROM public.profiles
  WHERE auth_user_id = auth.uid() AND role = 'coach';

  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'Only coaches can create diver profiles';
  END IF;

  -- Create unclaimed profile (full_name is set by trg_sync_profile_name).
  -- assigned_coach_name defaults to the creating coach; a coach can still
  -- reassign it later via update_diver_profile_by_coach.
  INSERT INTO public.profiles (
    first_name, last_name, email, role, status,
    date_of_birth, current_level, phone, parent_guardian_name,
    notes, created_by_coach_id, gender, assigned_coach_name
  )
  VALUES (
    TRIM(p_first_name),
    NULLIF(TRIM(COALESCE(p_last_name, '')), ''),
    NULLIF(TRIM(COALESCE(p_email, '')), ''),
    'diver',
    'unclaimed',
    p_date_of_birth,
    p_current_level,
    NULLIF(TRIM(COALESCE(p_phone, '')), ''),
    NULLIF(TRIM(COALESCE(p_parent_guardian, '')), ''),
    NULLIF(TRIM(COALESCE(p_notes, '')), ''),
    v_coach_id,
    NULLIF(TRIM(COALESCE(p_gender, '')), ''),
    v_coach_name
  )
  RETURNING id INTO v_profile_id;

  -- Add to roster immediately
  INSERT INTO public.roster (coach_id, diver_id)
  VALUES (v_coach_id, v_profile_id);

  RETURN v_profile_id;
END;
$$;
