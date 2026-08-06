-- =============================================
-- DIVING SKILLS — Migration v38: Coach read access to linked parent profiles
-- Run this ONCE in the Supabase SQL Editor on an existing database.
--
-- BUG: coaches were unable to see a linked parent's actual account email
-- (profiles.email) or phone, and the "Invite Parent" button never flipped
-- to "Parent Linked" state, even after a parent successfully claimed an
-- invite and a parent_diver row existed.
--
-- ROOT CAUSE: every SELECT policy on public.profiles is scoped to either
-- role = 'diver' ("coach reads roster divers", "authenticated lookup by
-- email"), role IN ('coach','super_user') ("coaches can read coach
-- profiles"), or auth.uid() = auth_user_id ("own read"). None of them
-- ever covered role = 'parent'. js/supabase.js getLinkedParent() embeds
-- profiles via parent_diver_parent_id_fkey — RLS silently resolves that
-- embed to NULL for a coach, even though "parent_diver: coach manages
-- their divers" (supabase-setup.sql) already grants the coach SELECT on
-- the parent_diver linkage row itself. This predates v37 — v37 never
-- touched the profiles table — but it went unnoticed until coaches
-- started actually linking parent accounts via the new automated invite
-- flow (0 parent accounts existed before, per the family-account rollout).
--
-- What this does:
--   Adds a profiles SELECT policy: a coach may read a profiles row with
--   role = 'parent' if that parent is linked (via parent_diver) to a
--   diver on the coach's own roster. Mirrors the existing
--   "profiles: coach reads roster divers" pattern.
-- =============================================

DROP POLICY IF EXISTS "profiles: coach reads linked parents" ON public.profiles;
CREATE POLICY "profiles: coach reads linked parents"
  ON public.profiles FOR SELECT
  USING (
    role = 'parent'
    AND EXISTS (
      SELECT 1 FROM public.parent_diver
      JOIN public.roster ON roster.diver_id = parent_diver.diver_id
      WHERE parent_diver.parent_id = profiles.id
        AND roster.coach_id = auth.uid()
    )
  );
