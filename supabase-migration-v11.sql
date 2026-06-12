-- =============================================
-- DIVING SKILLS — Migration v11: Add gender to profiles
-- Run this ONCE in the Supabase SQL Editor on an existing database.
--
-- NOTE: This was requested as "v10", but v10 already exists (the
-- first_name/last_name split migration). This is v11 to keep the
-- migration sequence intact.
--
-- What this does:
--   1. Adds a nullable gender column to profiles, constrained to
--      'Male', 'Female', 'Other' (or NULL).
--   2. Updates create_unclaimed_diver to accept p_gender.
--   3. Adds update_diver_gender RPC so coaches can edit the gender
--      of any diver on their roster (claimed or unclaimed).
-- =============================================

-- 1. New column + constraint
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS gender TEXT;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_gender_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_gender_check
  CHECK (gender IS NULL OR gender IN ('Male', 'Female', 'Other'));

-- 2. create_unclaimed_diver: accept p_gender. The parameter list is
-- changing, so the old function must be dropped first.
DROP FUNCTION IF EXISTS public.create_unclaimed_diver(TEXT, TEXT, TEXT, DATE, INTEGER, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.create_unclaimed_diver(
  p_first_name         TEXT,
  p_last_name          TEXT,
  p_email              TEXT,
  p_date_of_birth      DATE,
  p_current_level      INTEGER,
  p_phone              TEXT,
  p_parent_guardian    TEXT,
  p_notes              TEXT,
  p_gender             TEXT
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_coach_id  UUID;
  v_profile_id UUID;
BEGIN
  -- Caller must be an authenticated coach
  SELECT id INTO v_coach_id
  FROM public.profiles
  WHERE auth_user_id = auth.uid() AND role = 'coach';

  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'Only coaches can create diver profiles';
  END IF;

  -- Create unclaimed profile (full_name is set by trg_sync_profile_name)
  INSERT INTO public.profiles (
    first_name, last_name, email, role, status,
    date_of_birth, current_level, phone, parent_guardian_name,
    notes, created_by_coach_id, gender
  )
  VALUES (
    TRIM(p_first_name),
    NULLIF(TRIM(COALESCE(p_last_name, '')), ''),
    NULLIF(TRIM(COALESCE(p_email, '')), ''),
    'diver',
    'unclaimed',
    p_date_of_birth,
    p_current_level,
    NULLIF(TRIM(COALESCE(p_phone, '')), ''),
    NULLIF(TRIM(COALESCE(p_parent_guardian, '')), ''),
    NULLIF(TRIM(COALESCE(p_notes, '')), ''),
    v_coach_id,
    NULLIF(TRIM(COALESCE(p_gender, '')), '')
  )
  RETURNING id INTO v_profile_id;

  -- Add to roster immediately
  INSERT INTO public.roster (coach_id, diver_id)
  VALUES (v_coach_id, v_profile_id);

  RETURN v_profile_id;
END;
$$;

-- 3. update_diver_gender: lets a coach edit the gender of any diver on
-- their roster, regardless of claim status (RLS only allows coaches to
-- update unclaimed/pending profiles directly, so a SECURITY DEFINER RPC
-- is needed to cover active/claimed divers too).
CREATE OR REPLACE FUNCTION public.update_diver_gender(p_diver_id UUID, p_gender TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_coach_id UUID;
BEGIN
  SELECT id INTO v_coach_id
  FROM public.profiles
  WHERE auth_user_id = auth.uid() AND role = 'coach';

  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'Only coaches can edit diver profiles';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.roster
    WHERE coach_id = v_coach_id AND diver_id = p_diver_id
  ) THEN
    RAISE EXCEPTION 'You can only edit divers on your own roster';
  END IF;

  IF p_gender IS NOT NULL AND p_gender NOT IN ('Male', 'Female', 'Other') THEN
    RAISE EXCEPTION 'Invalid gender value';
  END IF;

  UPDATE public.profiles
  SET gender = p_gender
  WHERE id = p_diver_id;
END;
$$;
