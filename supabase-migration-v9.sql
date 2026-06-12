-- =============================================
-- DIVING SKILLS — Migration v9: Expose invite expiry to invite.html
-- Run this ONCE in the Supabase SQL Editor on an existing database.
-- Adds invite_token_expires_at to get_invite_info's return so the
-- client can compare it against the current time directly.
-- =============================================

-- The return row type is changing (new column added), so the existing
-- function must be dropped before it can be recreated.
DROP FUNCTION IF EXISTS public.get_invite_info(TEXT);

CREATE OR REPLACE FUNCTION public.get_invite_info(p_token TEXT)
RETURNS TABLE (
  diver_name              TEXT,
  current_level           INTEGER,
  invite_type             TEXT,
  coach_name              TEXT,
  invite_token_expires_at TIMESTAMPTZ,
  is_valid                BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.full_name,
    p.current_level,
    p.invite_type,
    c.full_name,
    p.invite_token_expires_at,
    (p.invite_token_expires_at IS NOT NULL AND p.invite_token_expires_at > now())
  FROM public.profiles p
  LEFT JOIN public.profiles c ON c.id = p.invited_by_coach_id
  WHERE p.invite_token = p_token;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_invite_info(TEXT) TO anon, authenticated;
