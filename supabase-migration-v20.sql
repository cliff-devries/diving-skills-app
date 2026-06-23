-- =============================================
-- DIVING SKILLS — Migration v20: Testing System Stage Independence
-- Run this ONCE in the Supabase SQL Editor (after v19).
-- Safe to re-run: uses DROP CONSTRAINT/TRIGGER IF EXISTS.
--
-- PROBLEM: The v4 constraint and v6 trigger enforce that tested_and_passed
-- requires skill_attained AND ready_for_test. The new testing system needs
-- these three stages to be fully independent — a coach can run a test
-- session without requiring divers to have Stage 1 or Stage 2 complete.
--
-- CHANGES:
--   1. Drop the stage-order CHECK constraint.
--   2. Make skill_attained and ready_for_test nullable (drop NOT NULL +
--      DEFAULT) so new testing rows start with NULL (never explicitly set).
--   3. Replace enforce_skill_stage_permissions() to remove the upward
--      cascade that auto-set skill_attained/ready_for_test when
--      tested_and_passed was true.
-- =============================================


-- =============================================
-- 1. DROP STAGE-ORDER CONSTRAINT
-- =============================================

ALTER TABLE public.skill_completions
  DROP CONSTRAINT IF EXISTS skill_completions_stage_order_chk;


-- =============================================
-- 2. MAKE STAGE FIELDS NULLABLE (no default)
-- Existing rows keep their current true/false values.
-- New rows created only by the testing system will have NULL for
-- skill_attained and ready_for_test until a coach/diver explicitly sets them.
-- =============================================

ALTER TABLE public.skill_completions
  ALTER COLUMN skill_attained  DROP NOT NULL,
  ALTER COLUMN skill_attained  DROP DEFAULT,
  ALTER COLUMN ready_for_test  DROP NOT NULL,
  ALTER COLUMN ready_for_test  DROP DEFAULT;


-- =============================================
-- 3. REPLACE TRIGGER — remove upward cascade
-- Keeps the non-coach protection (Stage 2/3 write-protected).
-- Removes the safety-net block that cascaded tested_and_passed → stages.
-- =============================================

CREATE OR REPLACE FUNCTION public.enforce_skill_stage_permissions()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role TEXT;
BEGIN
  SELECT role INTO v_role FROM public.profiles WHERE auth_user_id = auth.uid();

  -- Non-coaches cannot set or modify Stage 2 (ready_for_test) or
  -- Stage 3 (tested_and_passed) fields.
  IF v_role IS DISTINCT FROM 'coach' THEN
    IF TG_OP = 'UPDATE' THEN
      NEW.ready_for_test    := OLD.ready_for_test;
      NEW.ready_for_test_at := OLD.ready_for_test_at;
      NEW.ready_for_test_by := OLD.ready_for_test_by;
      NEW.tested_and_passed := OLD.tested_and_passed;
    ELSE
      -- INSERT by non-coach: leave ready_for_test NULL (not yet set by coach)
      NEW.ready_for_test    := NULL;
      NEW.ready_for_test_at := NULL;
      NEW.ready_for_test_by := NULL;
      NEW.tested_and_passed := FALSE;
    END IF;
  END IF;

  -- Upward cascade INTENTIONALLY REMOVED.
  -- Stage 1 (skill_attained), Stage 2 (ready_for_test), and
  -- Stage 3 (tested_and_passed) are now independent:
  --   Stage 1/2 are managed by divers/coaches via the skills screen.
  --   Stage 3 is set exclusively by the testing session system.

  RETURN NEW;
END;
$$;
