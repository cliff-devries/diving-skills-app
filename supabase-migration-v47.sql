-- ============================================================
-- Migration v47 — Shared practice plan view (#/view/:id in practice.html)
-- Run once in Supabase SQL editor. Safe to re-run (CREATE OR REPLACE).
--
-- WHY: dive_practice_plans' SELECT policy (migration v42) only allows the
-- owning coach, or any active coach for a 'club'-visibility plan — there
-- is no read access at all for parent/diver roles. The new #/view/:id
-- page needs to be viewable by "any logged-in coach, parent, or diver"
-- who has the link, without granting parents/divers the ability to
-- browse/list every plan in the club (which directly widening the base
-- table's RLS SELECT policy to all authenticated users would do).
--
-- FIX: a narrow SECURITY DEFINER RPC, the same pattern already used for
-- invite links (get_invite_info in migration v8) — it bypasses RLS
-- internally but only returns the ONE row matching the id you already
-- have (from the share link), never a list. Only requires a signed-in
-- session (auth.uid() IS NOT NULL); no role or roster check at all,
-- matching "any logged-in coach, parent, or diver can view".
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_shared_practice_plan(p_plan_id TEXT)
RETURNS SETOF public.dive_practice_plans
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to view this practice plan';
  END IF;

  RETURN QUERY
  SELECT * FROM public.dive_practice_plans WHERE id = p_plan_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_shared_practice_plan(TEXT) TO authenticated;
