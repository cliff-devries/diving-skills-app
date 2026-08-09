-- =============================================
-- DIVING SKILLS — Migration v45: Practice Plans "Coach" column
-- Run this ONCE in the Supabase SQL Editor. Purely additive (ADD COLUMN,
-- no drops) — existing data is untouched.
--
-- Background: the Practice Plans list now shows who created each plan
-- ("Cliff D." style). Rather than joining coach_id -> profiles.full_name
-- on every list render, the display name is computed once (from the
-- signed-in coach's own DB.coach.firstName/lastName) and stored directly
-- on the plan at creation time — see coachDisplayName() in practice.html.
-- Plans saved before this migration will just show blank/"—" for Coach
-- until they're re-saved (existing plan.coach_id is untouched either way).
-- =============================================

ALTER TABLE public.dive_practice_plans
  ADD COLUMN IF NOT EXISTS coach_name TEXT;
