-- =============================================
-- DIVING SKILLS — Migration v10: Split full_name into first_name/last_name
-- Run this ONCE in the Supabase SQL Editor on an existing database.
--
-- NOTE: This was requested as "v9", but v9 already exists and was already
-- applied (the get_invite_info expiry fix). This is v10 to keep the
-- migration sequence intact.
--
-- What this does:
--   1. Adds first_name / last_name columns to profiles.
--   2. Backfills first_name/last_name from existing full_name by splitting
--      on the first space.
--   3. Adds a trigger that keeps full_name in sync as "first_name last_name"
--      whenever first_name/last_name change, and (for rows/paths that only
--      ever set full_name, e.g. parent signup) derives first_name/last_name
--      from full_name automatically.
--   4. Updates create_unclaimed_diver to accept p_first_name/p_last_name
--      instead of p_full_name.
-- =============================================

-- 1. New columns
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS first_name TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_name  TEXT;

-- 2. Backfill from existing full_name (split on first space)
UPDATE public.profiles
SET
  first_name = COALESCE(first_name, split_part(trim(full_name), ' ', 1)),
  last_name  = COALESCE(
    last_name,
    CASE WHEN position(' ' IN trim(full_name)) > 0
      THEN trim(substring(trim(full_name) FROM position(' ' IN trim(full_name)) + 1))
      ELSE NULL
    END
  )
WHERE full_name IS NOT NULL;

-- 3. Keep full_name in sync with first_name/last_name (bidirectional)
CREATE OR REPLACE FUNCTION public.sync_profile_name()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_space_pos INTEGER;
BEGIN
  IF TG_OP = 'UPDATE'
     AND (NEW.first_name IS DISTINCT FROM OLD.first_name OR NEW.last_name IS DISTINCT FROM OLD.last_name)
     AND NEW.full_name IS NOT DISTINCT FROM OLD.full_name THEN
    -- first_name/last_name changed directly -> regenerate full_name
    NEW.full_name := trim(concat_ws(' ', NEW.first_name, NEW.last_name));
  ELSIF NEW.first_name IS NULL AND NEW.last_name IS NULL AND NEW.full_name IS NOT NULL THEN
    -- Only full_name was provided (e.g. parent signup via auth metadata) ->
    -- derive first_name/last_name from it.
    NEW.first_name := split_part(trim(NEW.full_name), ' ', 1);
    v_space_pos := position(' ' IN trim(NEW.full_name));
    NEW.last_name := CASE WHEN v_space_pos > 0
      THEN trim(substring(trim(NEW.full_name) FROM v_space_pos + 1))
      ELSE NULL
    END;
    NEW.full_name := trim(concat_ws(' ', NEW.first_name, NEW.last_name));
  ELSIF NEW.first_name IS NOT NULL OR NEW.last_name IS NOT NULL THEN
    -- first_name/last_name present -> full_name always reflects them
    NEW.full_name := trim(concat_ws(' ', NEW.first_name, NEW.last_name));
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_profile_name ON public.profiles;
CREATE TRIGGER trg_sync_profile_name
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.sync_profile_name();

-- 4. create_unclaimed_diver: accept p_first_name/p_last_name instead of p_full_name.
-- The parameter list is changing, so the old function must be dropped first.
DROP FUNCTION IF EXISTS public.create_unclaimed_diver(TEXT, TEXT, DATE, INTEGER, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.create_unclaimed_diver(
  p_first_name         TEXT,
  p_last_name          TEXT,
  p_email              TEXT,
  p_date_of_birth      DATE,
  p_current_level      INTEGER,
  p_phone              TEXT,
  p_parent_guardian    TEXT,
  p_notes              TEXT
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
    notes, created_by_coach_id
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
    v_coach_id
  )
  RETURNING id INTO v_profile_id;

  -- Add to roster immediately
  INSERT INTO public.roster (coach_id, diver_id)
  VALUES (v_coach_id, v_profile_id);

  RETURN v_profile_id;
END;
$$;
