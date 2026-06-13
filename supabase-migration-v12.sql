-- =============================================
-- DIVING SKILLS — Migration v12: Add skill_order to skills
-- Run this ONCE in the Supabase SQL Editor on an existing database.
--
-- What this does:
--   1. Adds a nullable skill_order column to skills, used to sort
--      skills in curriculum order instead of alphabetically.
--      Populate it with scripts/import-skill-order.js (matches each
--      row in skill_order.csv to a skill by skill_name + skill_level).
--   2. Adds an index to support sorting by skill_order.
-- =============================================

ALTER TABLE public.skills ADD COLUMN IF NOT EXISTS skill_order INTEGER;

CREATE INDEX IF NOT EXISTS idx_skills_order ON public.skills(skill_order);
