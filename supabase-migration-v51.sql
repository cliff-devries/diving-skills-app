-- ============================================================
-- Migration v51 — Skill Block redesign: per-skill minutes + snapshot
-- Run once in Supabase SQL editor. Safe to re-run (ADD COLUMN IF NOT
-- EXISTS is idempotent).
--
-- WHY: dive_practice_skill_blocks.skill_ids (migration v41) is a bare
-- TEXT[] of skill ids — the old "New Skill Block" form just checked
-- boxes next to DB.skills and resolved names/stations against the live
-- library at render time. The redesigned block editor needs each skill's
-- name/station/source snapshotted onto the block itself (so a block
-- still displays correctly even if the source skill is later renamed,
-- moved to another station, or deleted) plus a per-skill minutes value
-- the coach can edit independently of the library's own skill record.
-- A TEXT[] of ids can't hold that — it needs a JSONB array of objects.
--
-- FIX: add dive_practice_skill_blocks.skills (JSONB, default '[]'),
-- shaped as [{skillId, name, minutes, station, source}, ...]. skill_ids
-- is left in place, untouched — dropping it isn't necessary and this
-- app never modifies old migration files. practice.html's own
-- backfillBlockSkills() converts any block that still only has
-- skill_ids into the new shape client-side the first time it's loaded
-- (matching skills against the coach's library, defaulting minutes to
-- 5), so no server-side data migration is required here.
-- ============================================================

ALTER TABLE public.dive_practice_skill_blocks
  ADD COLUMN IF NOT EXISTS skills JSONB NOT NULL DEFAULT '[]';
