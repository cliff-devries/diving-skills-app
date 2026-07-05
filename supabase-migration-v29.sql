-- ============================================================
-- Migration v29 — remove_diver_from_roster RPC
-- Run once in Supabase SQL editor.
--
-- Atomically sets diver status to 'inactive' and deletes all
-- roster rows for that diver. Requires active coach or super_user.
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
