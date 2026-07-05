-- ============================================================
-- Migration v25 — Soft delete for skills, is_super_user on profiles
-- Run once in Supabase SQL editor.
-- Safe to re-run: all operations use IF NOT EXISTS / idempotent updates.
--
-- WHAT CHANGES:
--   skills:    add deleted_at (timestamptz, nullable) — soft delete flag
--   profiles:  add is_super_user (boolean, default false) — super user gate
--   profiles:  SET is_super_user = true for the head super user account
-- ============================================================


-- =============================================
-- 1. SKILLS — add deleted_at column
-- =============================================

ALTER TABLE public.skills
  ADD COLUMN IF NOT EXISTS deleted_at timestamptz DEFAULT NULL;


-- =============================================
-- 2. PROFILES — add is_super_user column
-- =============================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_super_user boolean NOT NULL DEFAULT false;


-- =============================================
-- 3. Set is_super_user = true for head super user
-- =============================================

UPDATE public.profiles
  SET is_super_user = true
  WHERE id = '7c9b201b-d85a-48fa-ab64-5f414b2b27b8';


-- =============================================
-- 4. RLS — allow any active coach to soft-delete skills
--    (sets deleted_at; actual row deletion not permitted via RLS)
-- =============================================

-- The existing skills UPDATE policy already allows coaches to update skills.
-- No additional RLS changes needed — deleted_at is just another column.
-- super user check is enforced in app code, not at the DB level.
