-- ============================================================
-- Migration v34 — widen profiles_status_check to all valid status values
-- Already applied directly in Supabase SQL Editor on 2026-07-28; this file
-- exists to track that change in the migration history. Safe to re-run —
-- DROP CONSTRAINT IF EXISTS means it won't fail if already applied.
--
-- The original constraint (v3) only allowed 'unclaimed', 'pending', 'active'.
-- reject_coach() (v17) and remove_diver_from_roster() (v29/v33) also set
-- 'rejected' and 'inactive', which were violating the CHECK constraint.
-- See CLAUDE.md — Database Notes for the full list of valid status values.
-- ============================================================

ALTER TABLE public.profiles
DROP CONSTRAINT IF EXISTS profiles_status_check;

ALTER TABLE public.profiles
ADD CONSTRAINT profiles_status_check
CHECK (status = ANY (ARRAY[
  'unclaimed'::text,
  'pending'::text,
  'active'::text,
  'inactive'::text,
  'rejected'::text
]));
