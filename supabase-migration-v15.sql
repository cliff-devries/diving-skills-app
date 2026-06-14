-- =============================================
-- DIVING SKILLS — Migration v15: Reset all skills to is_testable = true
-- Run this ONCE in the Supabase SQL Editor on an existing database.
--
-- What this does:
--   1. Resets is_testable to true for ALL skills, undoing the
--      skill_type-based defaults set in migration v14.
--   2. Coaches can now manually toggle the small number of supplemental
--      skills off from the Skills Library edit form.
-- =============================================

UPDATE public.skills SET is_testable = true;
