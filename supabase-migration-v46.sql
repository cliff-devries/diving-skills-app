-- ============================================================
-- Migration v46 — Fix generate_profile_invite roster restriction
-- Run once in Supabase SQL editor. Safe to re-run (CREATE OR REPLACE).
--
-- WHY: generate_profile_invite() (added in migration v8) still requires
-- the diver to be on the CALLING coach's roster:
--
--   IF NOT EXISTS (
--     SELECT 1 FROM public.roster
--     WHERE coach_id = v_coach_id AND diver_id = p_diver_id
--   ) THEN
--     RAISE EXCEPTION 'Diver not found in your roster';
--
-- That's a leftover from the pre-v24 single-coach-roster model. Migration
-- v24 moved the whole app to "any active coach can see/manage any diver"
-- (see its own header comment) and updated skill_completions/
-- skill_test_attempts/level_completions RLS accordingly, but this RPC
-- function was never touched — so "Invite Parent" on progress.html has
-- errored with "Diver not found in your roster" for any diver not on the
-- clicking coach's own roster ever since v24 shipped.
--
-- FIX: same "any active coach" authorization v24 already uses elsewhere,
-- and the roster-membership check is replaced with a plain "does this
-- diver profile exist" check — no roster table involved at all.
--
-- get_invite_info / complete_diver_invite / complete_parent_invite (also
-- added in v8) were checked and have no roster/coach-scoping logic at
-- all — they operate purely on the invite token, so they're unaffected
-- and are not touched here.
-- ============================================================

CREATE OR REPLACE FUNCTION public.generate_profile_invite(
  p_diver_id    UUID,
  p_invite_type TEXT
)
RETURNS TABLE (token TEXT, expires_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_coach_id  UUID;
  v_token     TEXT;
  v_expires   TIMESTAMPTZ;
BEGIN
  IF p_invite_type NOT IN ('diver', 'parent') THEN
    RAISE EXCEPTION 'Invalid invite type';
  END IF;

  -- Caller must be an active coach (or super user) — matches v24's
  -- club-wide "any active coach" model, not just this diver's roster coach.
  SELECT id INTO v_coach_id
  FROM public.profiles
  WHERE id = auth.uid() AND role IN ('coach', 'super_user') AND status = 'active';

  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'Only active coaches can generate invites';
  END IF;

  -- Diver must exist as a diver profile — roster membership no longer
  -- required (any active coach can invite a parent for any diver).
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_diver_id AND role = 'diver'
  ) THEN
    RAISE EXCEPTION 'Diver not found';
  END IF;

  v_token   := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  v_expires := now() + interval '7 days';

  UPDATE public.profiles
  SET invite_token            = v_token,
      invite_token_expires_at = v_expires,
      invite_type             = p_invite_type,
      invited_by_coach_id     = v_coach_id
  WHERE id = p_diver_id;

  RETURN QUERY SELECT v_token, v_expires;
END;
$$;

GRANT EXECUTE ON FUNCTION public.generate_profile_invite(UUID, TEXT) TO authenticated;
