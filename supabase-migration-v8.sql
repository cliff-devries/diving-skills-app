-- =============================================
-- DIVING SKILLS — Migration v8: Diver & Parent Self-Signup via Invite Links
-- Run this ONCE in the Supabase SQL Editor on an existing database.
-- =============================================


-- =============================================
-- 1. EXTEND profiles TABLE — invite fields
-- =============================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS invite_token TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS invite_token_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS invite_type TEXT CHECK (invite_type IN ('diver', 'parent')),
  ADD COLUMN IF NOT EXISTS invited_by_coach_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;


-- =============================================
-- 2. EXTEND parent_diver TABLE — relationship label
-- =============================================

ALTER TABLE public.parent_diver
  ADD COLUMN IF NOT EXISTS relationship TEXT;


-- =============================================
-- 3. RPC FUNCTIONS (SECURITY DEFINER)
-- =============================================

-- generate_profile_invite: coach generates (or regenerates) an invite token
-- for a diver on their roster. Token is a 32-char hex string, valid 7 days.
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

  -- Caller must be an authenticated coach
  SELECT id INTO v_coach_id
  FROM public.profiles
  WHERE auth_user_id = auth.uid() AND role = 'coach';

  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'Only coaches can generate invites';
  END IF;

  -- Diver must be on this coach's roster
  IF NOT EXISTS (
    SELECT 1 FROM public.roster
    WHERE coach_id = v_coach_id AND diver_id = p_diver_id
  ) THEN
    RAISE EXCEPTION 'Diver not found in your roster';
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


-- get_invite_info: public lookup of an invite token (no auth required).
-- Returns one row if the token exists, with `is_valid` indicating whether
-- it has not expired and not already been used.
CREATE OR REPLACE FUNCTION public.get_invite_info(p_token TEXT)
RETURNS TABLE (
  diver_name    TEXT,
  current_level INTEGER,
  invite_type   TEXT,
  coach_name    TEXT,
  is_valid      BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.full_name,
    p.current_level,
    p.invite_type,
    c.full_name,
    (p.invite_token_expires_at IS NOT NULL AND p.invite_token_expires_at > now())
  FROM public.profiles p
  LEFT JOIN public.profiles c ON c.id = p.invited_by_coach_id
  WHERE p.invite_token = p_token;
END;
$$;


-- complete_diver_invite: links the newly-created auth account (must already
-- have a session, created with { data: { claiming: 'true' } }) to the
-- unclaimed profile that owns this invite token, and consumes the token.
CREATE OR REPLACE FUNCTION public.complete_diver_invite(p_token TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_profile_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to complete this step';
  END IF;

  IF EXISTS (SELECT 1 FROM public.profiles WHERE auth_user_id = auth.uid()) THEN
    RAISE EXCEPTION 'This account is already linked to a profile';
  END IF;

  SELECT id INTO v_profile_id
  FROM public.profiles
  WHERE invite_token = p_token
    AND invite_type = 'diver'
    AND invite_token_expires_at > now()
    AND status = 'unclaimed';

  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'This invite link is invalid or has expired';
  END IF;

  UPDATE public.profiles
  SET auth_user_id            = auth.uid(),
      email                   = COALESCE(auth.jwt() ->> 'email', email),
      status                  = 'active',
      invite_token            = NULL,
      invite_token_expires_at = NULL,
      invite_type             = NULL
  WHERE id = v_profile_id;
END;
$$;


-- complete_parent_invite: links the signed-in parent's profile (created by
-- the normal handle_new_user trigger with role='parent') to the diver named
-- in this invite token via parent_diver, and consumes the token.
CREATE OR REPLACE FUNCTION public.complete_parent_invite(
  p_token        TEXT,
  p_relationship TEXT
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_diver_id  UUID;
  v_parent_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to complete this step';
  END IF;

  SELECT id INTO v_diver_id
  FROM public.profiles
  WHERE invite_token = p_token
    AND invite_type = 'parent'
    AND invite_token_expires_at > now();

  IF v_diver_id IS NULL THEN
    RAISE EXCEPTION 'This invite link is invalid or has expired';
  END IF;

  SELECT id INTO v_parent_id
  FROM public.profiles
  WHERE auth_user_id = auth.uid() AND role = 'parent';

  IF v_parent_id IS NULL THEN
    RAISE EXCEPTION 'Parent account setup is incomplete';
  END IF;

  INSERT INTO public.parent_diver (parent_id, diver_id, relationship)
  VALUES (v_parent_id, v_diver_id, p_relationship)
  ON CONFLICT (parent_id, diver_id) DO UPDATE SET relationship = EXCLUDED.relationship;

  UPDATE public.profiles
  SET invite_token            = NULL,
      invite_token_expires_at = NULL,
      invite_type             = NULL
  WHERE id = v_diver_id;
END;
$$;


-- =============================================
-- 4. GRANTS
-- =============================================

GRANT EXECUTE ON FUNCTION public.generate_profile_invite(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_invite_info(TEXT)               TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_diver_invite(TEXT)         TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_parent_invite(TEXT, TEXT)  TO authenticated;
