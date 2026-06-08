-- =============================================
-- DIVING SKILLS — Migration v3: Two-Phase Diver Profile Workflow
-- Run this ONCE in the Supabase SQL Editor on an existing database.
-- If starting fresh, run supabase-setup.sql instead.
-- =============================================


-- =============================================
-- 1. EXTEND profiles TABLE
-- Decouple profiles.id from auth.users so coaches can create
-- unclaimed diver profiles that have no auth account yet.
-- =============================================

-- Add auth_user_id (nullable FK to auth.users — null for unclaimed divers)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS auth_user_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL;

-- Backfill: for all existing profiles, auth_user_id = id (they were created via trigger)
UPDATE public.profiles SET auth_user_id = id WHERE auth_user_id IS NULL;

-- Drop the hard FK from profiles.id to auth.users so coaches can INSERT
-- unclaimed profiles that have no corresponding auth account.
-- (The constraint name is profiles_id_fkey by Postgres default naming.)
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_id_fkey;

-- Make email optional — coaches may not have an email for a new diver yet
ALTER TABLE public.profiles ALTER COLUMN email DROP NOT NULL;

-- New fields
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('unclaimed', 'pending', 'active')),
  ADD COLUMN IF NOT EXISTS date_of_birth DATE,
  ADD COLUMN IF NOT EXISTS phone TEXT,
  ADD COLUMN IF NOT EXISTS parent_guardian_name TEXT,
  ADD COLUMN IF NOT EXISTS notes TEXT,
  ADD COLUMN IF NOT EXISTS current_level INTEGER CHECK (current_level BETWEEN 0 AND 12),
  ADD COLUMN IF NOT EXISTS created_by_coach_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

-- Index new columns
CREATE INDEX IF NOT EXISTS idx_profiles_auth_user_id ON public.profiles(auth_user_id);
CREATE INDEX IF NOT EXISTS idx_profiles_status       ON public.profiles(status);


-- =============================================
-- 2. profile_claims TABLE
-- A diver who signed up submits a claim linking their new auth account
-- to an existing unclaimed profile. Coach approves or rejects it.
-- =============================================

CREATE TABLE IF NOT EXISTS public.profile_claims (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id    UUID NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
  auth_user_id  UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.profile_claims ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profile_claims: claimant insert"       ON public.profile_claims;
DROP POLICY IF EXISTS "profile_claims: claimant read own"     ON public.profile_claims;
DROP POLICY IF EXISTS "profile_claims: claimant delete own"   ON public.profile_claims;
DROP POLICY IF EXISTS "profile_claims: coach reads for roster" ON public.profile_claims;

-- Authenticated users can submit a claim
CREATE POLICY "profile_claims: claimant insert"
  ON public.profile_claims FOR INSERT
  WITH CHECK (auth.uid() = auth_user_id);

-- Claimant can see their own pending claim
CREATE POLICY "profile_claims: claimant read own"
  ON public.profile_claims FOR SELECT
  USING (auth.uid() = auth_user_id);

-- Claimant can withdraw their own claim
CREATE POLICY "profile_claims: claimant delete own"
  ON public.profile_claims FOR DELETE
  USING (auth.uid() = auth_user_id);

-- Coach can read claims for profiles they created
CREATE POLICY "profile_claims: coach reads for roster"
  ON public.profile_claims FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = profile_claims.profile_id
        AND p.created_by_coach_id = auth.uid()
    )
  );

CREATE INDEX IF NOT EXISTS idx_profile_claims_profile_id   ON public.profile_claims(profile_id);
CREATE INDEX IF NOT EXISTS idx_profile_claims_auth_user_id ON public.profile_claims(auth_user_id);


-- =============================================
-- 3. UPDATE RLS POLICIES ON profiles
-- Own-access policies now check auth_user_id (not id).
-- New policies let coaches create and manage unclaimed divers.
-- =============================================

DROP POLICY IF EXISTS "profiles: own read"                      ON public.profiles;
DROP POLICY IF EXISTS "profiles: own insert"                    ON public.profiles;
DROP POLICY IF EXISTS "profiles: own update"                    ON public.profiles;
DROP POLICY IF EXISTS "profiles: coach reads roster divers"     ON public.profiles;
DROP POLICY IF EXISTS "profiles: parent reads linked divers"    ON public.profiles;
DROP POLICY IF EXISTS "profiles: authenticated lookup by email" ON public.profiles;
DROP POLICY IF EXISTS "profiles: coach creates unclaimed"       ON public.profiles;
DROP POLICY IF EXISTS "profiles: coach updates unclaimed"       ON public.profiles;
DROP POLICY IF EXISTS "profiles: search unclaimed"              ON public.profiles;

-- Users can read their own profile via auth_user_id
CREATE POLICY "profiles: own read"
  ON public.profiles FOR SELECT
  USING (auth.uid() = auth_user_id);

-- The handle_new_user trigger inserts profiles; block direct inserts by regular users
CREATE POLICY "profiles: own insert"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = auth_user_id);

CREATE POLICY "profiles: own update"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = auth_user_id);

-- Coaches can read any profile on their roster (claimed or unclaimed)
CREATE POLICY "profiles: coach reads roster divers"
  ON public.profiles FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.roster
      WHERE roster.coach_id = auth.uid()
        AND roster.diver_id = profiles.id
    )
  );

-- Coaches can insert new unclaimed diver profiles
-- auth.uid() = coach's profiles.id because for triggered profiles id = auth_user_id = auth.uid()
CREATE POLICY "profiles: coach creates unclaimed"
  ON public.profiles FOR INSERT
  WITH CHECK (
    status = 'unclaimed'
    AND role = 'diver'
    AND created_by_coach_id = auth.uid()
  );

-- Coaches can update unclaimed profiles they created
CREATE POLICY "profiles: coach updates unclaimed"
  ON public.profiles FOR UPDATE
  USING (
    status IN ('unclaimed', 'pending')
    AND created_by_coach_id = auth.uid()
  );

-- Parents can read their linked divers
CREATE POLICY "profiles: parent reads linked divers"
  ON public.profiles FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.parent_diver
      WHERE parent_diver.parent_id = auth.uid()
        AND parent_diver.diver_id  = profiles.id
    )
  );

-- Any authenticated user can look up a diver profile by email (coaches use this)
CREATE POLICY "profiles: authenticated lookup by email"
  ON public.profiles FOR SELECT
  USING (auth.role() = 'authenticated' AND role = 'diver');

-- Any authenticated user can search unclaimed profiles (needed for the claim flow)
CREATE POLICY "profiles: search unclaimed"
  ON public.profiles FOR SELECT
  USING (
    auth.role() = 'authenticated'
    AND status IN ('unclaimed', 'pending')
  );


-- =============================================
-- 4. UPDATE handle_new_user TRIGGER
-- Sets both id and auth_user_id = NEW.id for triggered profiles.
-- Skips profile creation when the user is signing up to claim an
-- existing profile (pass { data: { claiming: 'true' } } in signUp()).
-- =============================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Divers signing up to claim an existing profile skip auto-creation.
  -- The claim approval flow links their auth account to the existing profile.
  IF COALESCE(NEW.raw_user_meta_data->>'claiming', 'false') = 'true' THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.profiles (id, auth_user_id, email, full_name, role, status)
  VALUES (
    NEW.id,
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'role', 'diver'),
    'active'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- =============================================
-- 5. RPC FUNCTIONS (SECURITY DEFINER — bypass RLS for complex writes)
-- =============================================

-- create_unclaimed_diver: atomically creates a profile + roster entry.
-- Called by coaches from the roster page.
CREATE OR REPLACE FUNCTION public.create_unclaimed_diver(
  p_full_name          TEXT,
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

  -- Create unclaimed profile
  INSERT INTO public.profiles (
    full_name, email, role, status,
    date_of_birth, current_level, phone, parent_guardian_name,
    notes, created_by_coach_id
  )
  VALUES (
    TRIM(p_full_name),
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


-- approve_profile_claim: links the claimant's auth account to the unclaimed profile.
-- Called by coaches from the dashboard.
CREATE OR REPLACE FUNCTION public.approve_profile_claim(p_claim_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_claim   RECORD;
  v_profile RECORD;
  v_coach_id UUID;
BEGIN
  -- Get calling coach's profile id
  SELECT id INTO v_coach_id FROM public.profiles WHERE auth_user_id = auth.uid();

  SELECT * INTO v_claim FROM public.profile_claims WHERE id = p_claim_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Claim not found'; END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = v_claim.profile_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;

  -- Only the coach who created this profile can approve
  IF v_profile.created_by_coach_id != v_coach_id THEN
    RAISE EXCEPTION 'Not authorized to approve this claim';
  END IF;

  -- Link auth account to profile
  UPDATE public.profiles
  SET auth_user_id = v_claim.auth_user_id,
      status       = 'active'
  WHERE id = v_claim.profile_id;

  -- Remove the pending claim
  DELETE FROM public.profile_claims WHERE id = p_claim_id;
END;
$$;


-- reject_profile_claim: rejects and removes a claim, profile stays unclaimed.
CREATE OR REPLACE FUNCTION public.reject_profile_claim(p_claim_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_claim   RECORD;
  v_profile RECORD;
  v_coach_id UUID;
BEGIN
  SELECT id INTO v_coach_id FROM public.profiles WHERE auth_user_id = auth.uid();

  SELECT * INTO v_claim FROM public.profile_claims WHERE id = p_claim_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Claim not found'; END IF;

  SELECT * INTO v_profile FROM public.profiles WHERE id = v_claim.profile_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Profile not found'; END IF;

  IF v_profile.created_by_coach_id != v_coach_id THEN
    RAISE EXCEPTION 'Not authorized to reject this claim';
  END IF;

  -- Reset profile status back to unclaimed
  UPDATE public.profiles SET status = 'unclaimed' WHERE id = v_claim.profile_id;

  -- Remove the claim
  DELETE FROM public.profile_claims WHERE id = p_claim_id;
END;
$$;
