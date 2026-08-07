-- =============================================
-- DIVING SKILLS — Migration v40: Atomic coach reassignment
-- Run this ONCE in the Supabase SQL Editor on an existing database.
--
-- PROBLEM: the Edit Diver form only ever updated profiles.assigned_coach_name
-- (free text) — it never touched the roster table, which is what actually
-- drives the "My Divers" dashboard count and the roster-linked coach lookup
-- (getDiverCoach). Reassigning a diver to a different coach via the text
-- field left the roster table pointing at the old coach, so the dashboard
-- count and the displayed coach name could disagree.
--
-- What this does:
--   Adds reassign_diver_coach(p_diver_id, p_new_coach_id), which updates
--   both roster and assigned_coach_name in one call.
--
--   roster has UNIQUE(coach_id, diver_id) but NOT UNIQUE(diver_id) — a
--   plain UPDATE ... SET coach_id = p_new_coach_id WHERE diver_id = ...
--   would throw a duplicate-key error if a diver ever ended up with more
--   than one roster row (or collide with an existing row for the new
--   coach). DELETE-then-INSERT sidesteps that: it always leaves exactly
--   one roster row for this diver, pointed at the new coach, regardless
--   of how many rows existed before.
-- =============================================

CREATE OR REPLACE FUNCTION public.reassign_diver_coach(
  p_diver_id     UUID,
  p_new_coach_id UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_coach_name TEXT;
BEGIN
  -- Caller must be an active coach or super_user
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE auth_user_id = auth.uid()
      AND role IN ('coach', 'super_user')
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Target must actually be an active coach — not just any UUID.
  SELECT full_name INTO v_new_coach_name
  FROM public.profiles
  WHERE id = p_new_coach_id
    AND role IN ('coach', 'super_user')
    AND status = 'active';

  IF v_new_coach_name IS NULL THEN
    RAISE EXCEPTION 'Selected coach is not valid';
  END IF;

  -- Replace this diver's roster link(s) with a single row for the new coach.
  DELETE FROM public.roster WHERE diver_id = p_diver_id;
  INSERT INTO public.roster (coach_id, diver_id) VALUES (p_new_coach_id, p_diver_id);

  -- Keep the display text in sync.
  UPDATE public.profiles
  SET assigned_coach_name = v_new_coach_name
  WHERE id = p_diver_id
    AND role = 'diver';
END;
$$;

GRANT EXECUTE ON FUNCTION public.reassign_diver_coach TO authenticated;
