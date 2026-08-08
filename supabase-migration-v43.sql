-- =============================================
-- DIVING SKILLS — Migration v43: find & fix stale level_completions rows
-- Run this ONCE in the Supabase SQL Editor. Read the whole file first —
-- Part 2 is a data-changing UPDATE, not a schema change.
--
-- Background: until this pass, Complete Session (testing.html) computed
-- a level's designation from whatever was scored in ONE sitting, not
-- from every testable skill in the level. A diver could end up with a
-- level_completions row claiming Bronze/Silver/Gold (or passed=true)
-- while skills in that level were still completely untested. The app
-- now always requires every testable skill in a level to be scored
-- before writing a level_completions row at all (see
-- App.computeLevelResult() in js/app.js) — but rows written by the OLD
-- logic before this fix are still sitting in the database and need a
-- one-time cleanup.
-- =============================================


-- =============================================
-- PART 1 — DIAGNOSTIC: find stale rows
-- Any level_completions row with a designation set, where the diver
-- does NOT have a scored skill_completions row for every testable skill
-- in that level, was computed from partial data under the old logic.
-- (Rows with designation IS NULL but passed=true are also worth a look
-- — see the second query below — since "plain Passed, no medal" is a
-- valid legitimate outcome under the OLD logic too if it was based on
-- a partial session.)
-- =============================================

SELECT
  lc.diver_id,
  p.full_name,
  lc.level,
  lc.designation,
  lc.average_score,
  lc.passed,
  COUNT(DISTINCT s.id)                                   AS total_testable_skills,
  COUNT(DISTINCT sc.skill_id)                            AS tested_skills,
  COUNT(DISTINCT s.id) - COUNT(DISTINCT sc.skill_id)     AS untested_skills
FROM level_completions lc
JOIN profiles p ON p.id = lc.diver_id
JOIN skills s
  ON s.skill_level = lc.level
  AND s.is_testable = true
  AND s.deleted_at IS NULL
LEFT JOIN skill_completions sc
  ON sc.diver_id = lc.diver_id
  AND sc.skill_id = s.id
  AND sc.latest_score IS NOT NULL
GROUP BY lc.diver_id, p.full_name, lc.level, lc.designation, lc.average_score, lc.passed
HAVING COUNT(DISTINCT sc.skill_id) < COUNT(DISTINCT s.id)
ORDER BY p.full_name, lc.level;

-- Same check, but also catches rows that claim passed=true with no
-- designation ("plain Passed") on partial data — the diagnostic above
-- already includes these (it doesn't filter on designation IS NOT
-- NULL), this is just an easy way to see JUST that subset:
--
-- SELECT * FROM (<query above as a CTE>) x WHERE designation IS NULL AND passed = true;


-- =============================================
-- PART 2 — FIX: clear the incorrect result on stale rows
-- ** Review Part 1's output before running this. ** It updates every
-- level_completions row that Part 1's HAVING clause would return,
-- setting designation/average_score to NULL and passed to false — i.e.
-- "no longer claiming a result", NOT "failed". A coach re-opening this
-- level in testing.html and clicking Complete Session will recompute it
-- correctly (Incomplete, since skills are still untested) and, unlike
-- this UPDATE, that write path won't insert an incomplete row at all.
--
-- Alternative to consider instead of this UPDATE: DELETE these rows
-- entirely. The app's new logic never writes a level_completions row
-- for an incomplete level in the first place, so a row that merely has
-- designation/passed cleared is still not a state the app produces on
-- its own — it'll keep showing up in stats.html's "reports available"
-- list (which lists any level_completions row) even though nothing was
-- actually finalized. If that list should NOT include these levels,
-- delete instead of update:
--
--   DELETE FROM level_completions lc
--   USING (
--     SELECT lc2.id
--     FROM level_completions lc2
--     JOIN skills s ON s.skill_level = lc2.level AND s.is_testable = true AND s.deleted_at IS NULL
--     LEFT JOIN skill_completions sc ON sc.diver_id = lc2.diver_id AND sc.skill_id = s.id AND sc.latest_score IS NOT NULL
--     GROUP BY lc2.id
--     HAVING COUNT(DISTINCT sc.skill_id) < COUNT(DISTINCT s.id)
--   ) stale
--   WHERE lc.id = stale.id;

UPDATE level_completions lc
SET designation = NULL,
    average_score = NULL,
    passed = false
FROM (
  SELECT lc2.id
  FROM level_completions lc2
  JOIN skills s
    ON s.skill_level = lc2.level
    AND s.is_testable = true
    AND s.deleted_at IS NULL
  LEFT JOIN skill_completions sc
    ON sc.diver_id = lc2.diver_id
    AND sc.skill_id = s.id
    AND sc.latest_score IS NOT NULL
  GROUP BY lc2.id
  HAVING COUNT(DISTINCT sc.skill_id) < COUNT(DISTINCT s.id)
) AS stale
WHERE lc.id = stale.id;
