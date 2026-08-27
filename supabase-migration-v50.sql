-- ============================================================
-- Migration v50 — Public (anonymous) sharing for practice plans
-- Run once in Supabase SQL editor. Safe to re-run (CREATE OR REPLACE).
--
-- WHY: get_shared_practice_plan (migration v47) requires a signed-in
-- session and returns the plan unconditionally — "any logged-in coach,
-- parent, or diver with the link" can view it, but nobody without an
-- account can, and every plan is reachable this way, not just ones the
-- coach chose to publish. The new requirement is a real public-share
-- link: divedrills.com/practice.html#/view/[planId] must work with NO
-- login at all, but ONLY for plans the coach explicitly marked shared.
--
-- FIX: add dive_practice_plans.is_shared (default false, so every
-- existing plan stays private), and recreate the RPC to (a) drop the
-- auth.uid() requirement entirely and (b) only return a row when
-- is_shared = true. It's still SECURITY DEFINER — that's what lets it
-- bypass RLS for an anonymous caller — but the is_shared filter (not
-- auth) is now what limits exposure to a single row the coach opted
-- into publishing, never a list, never an unshared plan.
-- ============================================================

ALTER TABLE public.dive_practice_plans
  ADD COLUMN IF NOT EXISTS is_shared BOOLEAN NOT NULL DEFAULT false;

DROP FUNCTION IF EXISTS public.get_shared_practice_plan(TEXT);

CREATE OR REPLACE FUNCTION public.get_shared_practice_plan(p_plan_id TEXT)
RETURNS SETOF public.dive_practice_plans
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM public.dive_practice_plans
  WHERE id = p_plan_id AND is_shared = true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_shared_practice_plan(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.get_shared_practice_plan(TEXT) TO authenticated;
