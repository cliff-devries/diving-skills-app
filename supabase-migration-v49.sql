-- ============================================================
-- Migration v49 — Bulk "Invite All Parents" support (roster.html)
-- Run once in Supabase SQL editor. Safe to re-run (CREATE OR REPLACE).
--
-- WHY: the new "Invite All Parents" button needs to find every active
-- diver that (a) has a parent email on file and (b) hasn't already been
-- invited or linked to a parent — club-wide, matching the "any active
-- coach can see/manage any diver" model (migration v24). A client-side
-- query can't do this correctly: the "already linked" check depends on
-- parent_diver, whose RLS ("parent_diver: coach manages their divers",
-- supabase-setup.sql) is still scoped to the CALLING coach's own roster
-- — v24's own header comment lists parent_diver under "WHAT DOES NOT
-- CHANGE". A coach querying it directly would only see links for divers
-- on their own roster and could wrongly re-invite a parent already
-- linked via another coach's roster assignment.
--
-- FIX: a SECURITY DEFINER RPC (same pattern as generate_profile_invite /
-- get_invite_info) that computes eligibility server-side, bypassing RLS
-- internally, gated only on "caller is an active coach" like every other
-- club-wide read in this app.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_uninvited_divers_with_parent_email()
RETURNS TABLE (
  id           UUID,
  full_name    TEXT,
  first_name   TEXT,
  last_name    TEXT,
  nickname     TEXT,
  parent_email TEXT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Table alias required here (not just style): RETURNS TABLE (id UUID, ...)
  -- above declares an implicit `id` OUT-parameter variable in scope for
  -- the whole function body, which collides with a bare `id` column
  -- reference and raises "column reference 'id' is ambiguous".
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles prof
    WHERE prof.id = auth.uid() AND prof.role IN ('coach', 'super_user') AND prof.status = 'active'
  ) THEN
    RAISE EXCEPTION 'Only active coaches can do this';
  END IF;

  RETURN QUERY
  SELECT p.id, p.full_name, p.first_name, p.last_name, p.nickname, p.parent_email
  FROM public.profiles p
  WHERE p.role = 'diver'
    AND p.status = 'active'
    AND p.parent_email IS NOT NULL
    AND p.parent_email != ''
    AND NOT EXISTS (SELECT 1 FROM public.parent_diver pd WHERE pd.diver_id = p.id)
    AND (p.invite_token IS NULL OR p.invite_type != 'parent')
  ORDER BY p.last_name, p.first_name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_uninvited_divers_with_parent_email() TO authenticated;
