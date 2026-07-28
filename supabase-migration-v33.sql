-- ============================================================
-- Migration v33 — recreate remove_diver_from_roster() as SECURITY DEFINER
-- Run once in Supabase SQL editor.
--
-- Fixes: "new row for relation profiles violates row level security
-- policy" when a coach removes a diver from the roster. The function
-- must run with the definer's privileges (not the calling coach's) so
-- the UPDATE on public.profiles can bypass RLS after the authorization
-- check below has already verified the caller is an active coach.
-- ============================================================

CREATE OR REPLACE FUNCTION public.remove_diver_from_roster(p_diver_id UUID)
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
    RAISE EXCEPTION 'Only active coaches can remove divers from the roster';
  END IF;

  UPDATE public.profiles
  SET status = 'inactive'
  WHERE id = p_diver_id AND role = 'diver';

  DELETE FROM public.roster WHERE diver_id = p_diver_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.remove_diver_from_roster TO authenticated;
