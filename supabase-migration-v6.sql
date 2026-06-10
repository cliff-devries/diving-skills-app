-- =============================================
-- DIVING SKILLS — Migration v6: Stage-order safety net
-- Run this ONCE in the Supabase SQL Editor on an existing database
-- (after supabase-migration-v5.sql).
-- Safe to re-run: replaces the trigger function with CREATE OR REPLACE.
--
-- PROBLEM: skill_completions_stage_order_chk requires
--   ready_for_test    => skill_attained
--   tested_and_passed => skill_attained AND ready_for_test
--
-- When a coach marks "Ready for Test" for a diver/skill that has no
-- skill_completions row yet, the upsert INSERTs a new row with
-- ready_for_test = true but skill_attained defaults to false (column
-- default), violating skill_completions_stage_order_chk:
--   "new row for relation skill_completions violates check constraint
--    skill_completions_stage_order_chk"
--
-- FIX: extend enforce_skill_stage_permissions() (from v4) so that setting
-- a later stage true automatically implies the earlier stage(s) are true
-- too, backfilling attribution fields if they're missing.
-- =============================================

CREATE OR REPLACE FUNCTION public.enforce_skill_stage_permissions()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role TEXT;
BEGIN
  SELECT role INTO v_role FROM public.profiles WHERE auth_user_id = auth.uid();

  -- Non-coaches can't set/modify Stage 2 or Stage 3 fields directly.
  IF v_role IS DISTINCT FROM 'coach' THEN
    IF TG_OP = 'UPDATE' THEN
      NEW.ready_for_test    := OLD.ready_for_test;
      NEW.ready_for_test_at := OLD.ready_for_test_at;
      NEW.ready_for_test_by := OLD.ready_for_test_by;
      NEW.tested_and_passed := OLD.tested_and_passed;
    ELSE
      NEW.ready_for_test    := FALSE;
      NEW.ready_for_test_at := NULL;
      NEW.ready_for_test_by := NULL;
      NEW.tested_and_passed := FALSE;
    END IF;
  END IF;

  -- Stage-order safety net: marking a later stage true implies the
  -- earlier stage(s) are also true, so skill_completions_stage_order_chk
  -- can never be violated regardless of which fields the upsert sent.
  IF NEW.tested_and_passed AND NOT NEW.ready_for_test THEN
    NEW.ready_for_test    := TRUE;
    NEW.ready_for_test_at := COALESCE(NEW.ready_for_test_at, NOW());
    NEW.ready_for_test_by := COALESCE(NEW.ready_for_test_by, NEW.skill_attained_by);
  END IF;

  IF NEW.ready_for_test AND NOT NEW.skill_attained THEN
    NEW.skill_attained    := TRUE;
    NEW.skill_attained_at := COALESCE(NEW.skill_attained_at, NOW());
    NEW.skill_attained_by := COALESCE(NEW.skill_attained_by, NEW.ready_for_test_by);
  END IF;

  RETURN NEW;
END;
$$;
