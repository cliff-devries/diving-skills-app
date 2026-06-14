-- =============================================
-- DIVING SKILLS — Migration v14: Add is_testable to skills
-- Run this ONCE in the Supabase SQL Editor on an existing database.
--
-- What this does:
--   1. Adds an is_testable boolean column to skills (defaults to true).
--   2. Sets smart defaults by skill_type — Games, Bonus, Conditioning,
--      and Flexibility skills are marked as supplemental
--      (is_testable = false); all curriculum skill types are marked
--      as testable (is_testable = true).
-- =============================================

ALTER TABLE public.skills ADD COLUMN IF NOT EXISTS is_testable BOOLEAN NOT NULL DEFAULT true;

UPDATE public.skills SET is_testable = false
  WHERE skill_type IN ('Games', 'Bonus', 'Conditioning', 'Flexibility');

UPDATE public.skills SET is_testable = true
  WHERE skill_type IN (
    'Basics', 'Trampoline', 'Trampoline in Belt', 'Dryboard', 'Dryboard in Belt',
    'Dry Platform', '1m Platform', '1m Platform in Belt', '1m Springboard',
    '3m Springboard', 'Platform', 'Pool'
  );
