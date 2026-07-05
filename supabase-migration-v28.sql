-- ============================================================
-- Migration v28 — AQUA age auto-calculation
-- Run once in Supabase SQL editor.
--
-- AQUA age = current calendar year minus diver's birth year.
-- Stored as a text string (e.g. '14', '16') or 'TBD'.
--
-- WHAT THIS DOES:
--   1. Bulk-updates aqua_group for all existing diver profiles
--      from their date_of_birth.
--   2. Creates update_all_aqua_groups() SECURITY DEFINER RPC
--      so super users can re-run the bulk update from the UI.
-- ============================================================

-- Step 1: Bulk update all existing divers
UPDATE public.profiles
SET aqua_group =
  CASE
    WHEN date_of_birth IS NOT NULL
    THEN (EXTRACT(YEAR FROM NOW()) - EXTRACT(YEAR FROM date_of_birth))::text
    ELSE 'TBD'
  END
WHERE role = 'diver';

-- Step 2: SECURITY DEFINER function for super-user-triggered bulk update
CREATE OR REPLACE FUNCTION public.update_all_aqua_groups()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  updated_count integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE auth_user_id = auth.uid()
      AND role = 'super_user'
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Only super users can bulk-update AQUA ages';
  END IF;

  UPDATE public.profiles
  SET aqua_group =
    CASE
      WHEN date_of_birth IS NOT NULL
      THEN (EXTRACT(YEAR FROM NOW()) - EXTRACT(YEAR FROM date_of_birth))::text
      ELSE 'TBD'
    END
  WHERE role = 'diver';

  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN updated_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_all_aqua_groups TO authenticated;
