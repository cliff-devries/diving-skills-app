-- ============================================================
-- Migration v27b — Recreate update_diver_profile_by_coach (standalone)
-- Run once in Supabase SQL editor.
-- No dependencies — inlines the auth check, does not require is_active_coach().
--
-- This is a standalone alternative to v27.sql for environments where
-- v26-fix may not have been applied yet.
-- ============================================================

-- Drop both the old 8-param signature and the new 11-param signature
-- (in case either version exists from a previous migration run).
DROP FUNCTION IF EXISTS public.update_diver_profile_by_coach(
  uuid, integer, text, text, date, text, text, text
);
DROP FUNCTION IF EXISTS public.update_diver_profile_by_coach(
  uuid, text, text, date, integer, text, text, date, text, text, text
);

CREATE OR REPLACE FUNCTION public.update_diver_profile_by_coach(
  p_diver_id            UUID,
  p_first_name          TEXT,
  p_last_name           TEXT,
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
