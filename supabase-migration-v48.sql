-- ============================================================
-- Migration v48 — Super-user bypass on update/delete RLS policies
-- Run once in Supabase SQL editor. Safe to re-run (DROP + CREATE).
--
-- WHY: DivePractice's UI (isMine()) is being widened so a super user sees
-- Delete on every practice plan and Edit/Delete on every custom skill,
-- regardless of who owns it. That's cosmetic only — the actual UPDATE/
-- DELETE policies on dive_practice_plans (migration v42) and the shared
-- "own update"/"own delete" policies applied to dive_practice_skills (and
-- every other club-wide shared table, also from v42's policy loop) use
-- USING (coach_id = auth.uid()) with no super-user exception, so those
-- calls would be silently rejected by RLS (0 rows affected) even with the
-- buttons showing.
--
-- FIX: add an OR EXISTS(...is_super_user...) clause to the update/delete
-- policies, the same super-user check v42 already uses for
-- dive_practice_plans' superuser-visibility SELECT branch. Read/insert
-- policies are untouched — this only widens who may modify/remove an
-- existing row that isn't theirs.
-- ============================================================

DROP POLICY IF EXISTS "dive_practice_plans: own update" ON public.dive_practice_plans;
DROP POLICY IF EXISTS "dive_practice_plans: own delete" ON public.dive_practice_plans;

CREATE POLICY "dive_practice_plans: own update"
  ON public.dive_practice_plans FOR UPDATE
  USING (
    coach_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_super_user = true)
  );

CREATE POLICY "dive_practice_plans: own delete"
  ON public.dive_practice_plans FOR DELETE
  USING (
    coach_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_super_user = true)
  );

-- Same bypass for every other club-wide shared table's own-update/own-delete
-- policies (dive_practice_skills is the one Fix 2 needs; the rest are swept
-- in together since they were created by the same loop in v42 and should
-- stay consistent with each other).
DO $$
DECLARE
  t TEXT;
  shared_tables TEXT[] := ARRAY[
    'dive_practice_categories',
    'dive_practice_skills',
    'dive_practice_skill_blocks',
    'dive_practice_locations',
    'dive_practice_announcements',
    'dive_practice_quotes',
    'dive_practice_emphasis',
    'dive_practice_notes',
    'dive_practice_groups'
  ];
BEGIN
  FOREACH t IN ARRAY shared_tables LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || ': own update', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || ': own delete', t);

    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR UPDATE USING (
         coach_id = auth.uid()
         OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_super_user = true)
       )', t || ': own update', t
    );
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR DELETE USING (
         coach_id = auth.uid()
         OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_super_user = true)
       )', t || ': own delete', t
    );
  END LOOP;
END $$;
