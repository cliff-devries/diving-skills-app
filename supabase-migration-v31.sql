-- Migration v31: Add passed column to level_completions
--
-- A level is "passed" only if ALL scored skills have a score >= 5.0.
-- Existing rows default to true (they were saved under the old logic
-- where every saved result was treated as a pass).

ALTER TABLE public.level_completions
  ADD COLUMN IF NOT EXISTS passed boolean NOT NULL DEFAULT true;
