-- =============================================
-- DIVING SKILLS — Migration v36: Diver nickname
-- Run this ONCE in the Supabase SQL Editor on an existing database.
--
-- What this does:
--   1. Adds profiles.nickname (optional, free text).
--   2. Recreates update_diver_profile_by_coach() with a new p_nickname
--      parameter so coaches can set it from the Edit Diver Profile form.
-- =============================================

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS nickname TEXT;

-- Drop every prior signature of update_diver_profile_by_coach before
-- recreating it with the added p_nickname parameter.
DROP FUNCTION IF EXISTS public.update_diver_profile_by_coach(
  uuid, integer, text, text, date, text, text, text
);
DROP FUNCTION IF EXISTS public.update_diver_profile_by_coach(
  uuid, text, text, date, integer, text, text, date, text, text, text
);
DROP FUNCTION IF EXISTS public.update_diver_profile_by_coach(
  uuid, text, text, text, date, integer, text, text, date, text, text, text
);

CREATE OR REPLACE FUNCTION public.update_diver_profile_by_coach(
  p_diver_id            UUID,
  p_first_name          TEXT,
  p_last_name           TEXT,
  p_nickname            TEXT,
  p_date_of_birth       DATE,
  p_current_level       INTEGER,
  p_diver_group         TEXT,
  p_assigned_coach_name TEXT,
  p_start_date          DATE,
  p_parent_email        TEXT,
  p_parent_phone        TEXT,
  p_aqua_group          TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE auth_user_id = auth.uid()
      AND role IN ('coach', 'super_user')
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  UPDATE public.profiles SET
    first_name          = NULLIF(TRIM(COALESCE(p_first_name, '')), ''),
    last_name           = NULLIF(TRIM(COALESCE(p_last_name, '')), ''),
    full_name           = TRIM(CONCAT_WS(' ', NULLIF(TRIM(COALESCE(p_first_name,'')), ''), NULLIF(TRIM(COALESCE(p_last_name,'')), ''))),
    nickname            = NULLIF(TRIM(COALESCE(p_nickname, '')), ''),
    date_of_birth       = p_date_of_birth,
    current_level       = p_current_level,
    diver_group         = p_diver_group,
    assigned_coach_name = p_assigned_coach_name,
    start_date          = p_start_date,
    parent_email        = p_parent_email,
    parent_phone        = p_parent_phone,
    aqua_group          = COALESCE(p_aqua_group, 'TBD')
  WHERE id = p_diver_id
    AND role = 'diver';
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_diver_profile_by_coach TO authenticated;
