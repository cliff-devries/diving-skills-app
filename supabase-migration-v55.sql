-- ============================================================
-- Migration v55 — DiveCRM sign-up form fields
-- Run once in the Supabase SQL editor (paste this file's text, not a .patch).
-- Safe to re-run: columns use IF NOT EXISTS / IF EXISTS, functions use
-- CREATE OR REPLACE.
--
-- WHAT THIS CHANGES
--   crm_contacts (the parent / guardian, shared by siblings) gains:
--     last_name, street_address, city, zip_code,
--     emergency_contact_name, emergency_contact_phone
--   crm_leads (the diver) gains:
--     signed_up_at, school_district, graduation_year, allergies_medical,
--     prior_diving_experience, prior_gymnastics_experience, diving_location,
--     aau_number, participates_in_competitions
--   crm_leads loses diver_email and diver_phone.
--
--   Already covered by existing columns, so NOT duplicated:
--     Diver's Birthdate                  -> crm_leads.date_of_birth
--     How did you find Upstate Diving?   -> crm_leads.source
--
-- WARNING: DROP COLUMN permanently deletes any diver email / phone already
-- stored on leads. Export from the Contacts tab or run
--   SELECT id, first_name, last_name, diver_email, diver_phone FROM crm_leads
--   WHERE diver_email IS NOT NULL OR diver_phone IS NOT NULL;
-- first if you need to keep them.
--
-- crm_import_leads and crm_convert_lead_to_diver are replaced below because
-- both referenced the dropped columns (the convert function would otherwise
-- fail on every call). Their behaviour is otherwise unchanged. Table
-- policies are untouched: v53's explicit SELECT/INSERT/UPDATE/DELETE
-- policies already cover the new columns.
--
-- PRIVACY: allergies / medical conditions and the home address are stored on
-- minors. They stay inside the coach-only CRM tables and, like CRM notes,
-- are deliberately NOT copied to profiles on conversion.
-- ============================================================


-- =============================================
-- 1. NEW COLUMNS
-- =============================================

ALTER TABLE public.crm_contacts
  ADD COLUMN IF NOT EXISTS last_name               TEXT,
  ADD COLUMN IF NOT EXISTS street_address          TEXT,
  ADD COLUMN IF NOT EXISTS city                    TEXT,
  ADD COLUMN IF NOT EXISTS zip_code                TEXT,
  ADD COLUMN IF NOT EXISTS emergency_contact_name  TEXT,
  ADD COLUMN IF NOT EXISTS emergency_contact_phone TEXT;

ALTER TABLE public.crm_leads
  ADD COLUMN IF NOT EXISTS signed_up_at                 TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS school_district              TEXT,
  ADD COLUMN IF NOT EXISTS graduation_year              INTEGER,
  ADD COLUMN IF NOT EXISTS allergies_medical            TEXT,
  ADD COLUMN IF NOT EXISTS prior_diving_experience      TEXT,
  ADD COLUMN IF NOT EXISTS prior_gymnastics_experience  TEXT,
  ADD COLUMN IF NOT EXISTS diving_location              TEXT,
  ADD COLUMN IF NOT EXISTS aau_number                   TEXT,
  ADD COLUMN IF NOT EXISTS participates_in_competitions BOOLEAN;

ALTER TABLE public.crm_leads DROP CONSTRAINT IF EXISTS crm_leads_graduation_year_check;
ALTER TABLE public.crm_leads
  ADD CONSTRAINT crm_leads_graduation_year_check
  CHECK (graduation_year IS NULL OR graduation_year BETWEEN 1990 AND 2100);


-- =============================================
-- 2. REPLACE THE TWO FUNCTIONS THAT USE diver_email / diver_phone
--    (must happen before the columns are dropped)
-- =============================================

-- Each row is a JSON object. Keys:
--   first_name (required), last_name, parent_name, parent_last_name,
--   parent_email, parent_phone, street_address, city, zip_code,
--   emergency_contact_name, emergency_contact_phone,
--   date_of_birth (YYYY-MM-DD), gender, source, campaign, notes, stage,
--   signed_up_at, school_district, graduation_year, allergies_medical,
--   prior_diving_experience, prior_gymnastics_experience, diving_location,
--   aau_number, participates_in_competitions (yes/no/true/false)
-- Contact matching, duplicate skipping and stage rules are unchanged from v53.
-- Address / emergency fields only fill blanks on an existing contact.
CREATE OR REPLACE FUNCTION public.crm_import_leads(
  p_rows             JSONB,
  p_default_source   TEXT DEFAULT NULL,
  p_default_campaign TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_coach     UUID := public.crm_current_coach_id();
  v_item      RECORD;
  v_first     TEXT;
  v_last      TEXT;
  v_pname     TEXT;
  v_plast     TEXT;
  v_pemail    TEXT;
  v_pphone    TEXT;
  v_street    TEXT;
  v_city      TEXT;
  v_zip       TEXT;
  v_ecname    TEXT;
  v_ecphone   TEXT;
  v_dob       DATE;
  v_gender    TEXT;
  v_stage     TEXT;
  v_signup    TIMESTAMPTZ;
  v_gradyear  INTEGER;
  v_comp      BOOLEAN;
  v_comp_txt  TEXT;
  v_contact   UUID;
  v_lead      UUID;
  v_inserted  INT := 0;
  v_skipped   INT := 0;
  v_contacts  INT := 0;
  v_ids       JSONB := '[]'::jsonb;
  v_skiplist  JSONB := '[]'::jsonb;
BEGIN
  IF v_coach IS NULL THEN
    RAISE EXCEPTION 'Only active coaches can do this';
  END IF;
  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'p_rows must be a JSON array';
  END IF;
  IF jsonb_array_length(p_rows) > 1000 THEN
    RAISE EXCEPTION 'Import at most 1000 rows at a time';
  END IF;

  FOR v_item IN
    SELECT t.value AS item, t.ordinality AS idx
    FROM jsonb_array_elements(p_rows) WITH ORDINALITY AS t(value, ordinality)
  LOOP
    v_first   := NULLIF(btrim(COALESCE(v_item.item->>'first_name', '')), '');
    v_last    := NULLIF(btrim(COALESCE(v_item.item->>'last_name', '')), '');
    v_pname   := NULLIF(btrim(COALESCE(v_item.item->>'parent_name', '')), '');
    v_plast   := NULLIF(btrim(COALESCE(v_item.item->>'parent_last_name', '')), '');
    v_pemail  := lower(NULLIF(btrim(COALESCE(v_item.item->>'parent_email', '')), ''));
    v_pphone  := NULLIF(btrim(COALESCE(v_item.item->>'parent_phone', '')), '');
    v_street  := NULLIF(btrim(COALESCE(v_item.item->>'street_address', '')), '');
    v_city    := NULLIF(btrim(COALESCE(v_item.item->>'city', '')), '');
    v_zip     := NULLIF(btrim(COALESCE(v_item.item->>'zip_code', '')), '');
    v_ecname  := NULLIF(btrim(COALESCE(v_item.item->>'emergency_contact_name', '')), '');
    v_ecphone := NULLIF(btrim(COALESCE(v_item.item->>'emergency_contact_phone', '')), '');

    IF v_first IS NULL THEN
      v_skipped  := v_skipped + 1;
      v_skiplist := v_skiplist || jsonb_build_object('row', v_item.idx, 'reason', 'Missing first name');
      CONTINUE;
    END IF;

    v_dob := NULL;
    BEGIN
      v_dob := NULLIF(btrim(COALESCE(v_item.item->>'date_of_birth', '')), '')::date;
    EXCEPTION WHEN others THEN
      v_dob := NULL;
    END;

    v_signup := NULL;
    BEGIN
      v_signup := NULLIF(btrim(COALESCE(v_item.item->>'signed_up_at', '')), '')::timestamptz;
    EXCEPTION WHEN others THEN
      v_signup := NULL;
    END;

    v_gradyear := NULL;
    BEGIN
      v_gradyear := NULLIF(btrim(COALESCE(v_item.item->>'graduation_year', '')), '')::integer;
    EXCEPTION WHEN others THEN
      v_gradyear := NULL;
    END;
    IF v_gradyear IS NOT NULL AND (v_gradyear < 1990 OR v_gradyear > 2100) THEN
      v_gradyear := NULL;
    END IF;

    v_comp_txt := lower(btrim(COALESCE(v_item.item->>'participates_in_competitions', '')));
    v_comp := CASE
                WHEN v_comp_txt IN ('yes', 'y', 'true', 't', '1') THEN TRUE
                WHEN v_comp_txt IN ('no', 'n', 'false', 'f', '0') THEN FALSE
                ELSE NULL END;

    v_gender := CASE lower(btrim(COALESCE(v_item.item->>'gender', '')))
                  WHEN 'male' THEN 'Male' WHEN 'm' THEN 'Male'
                  WHEN 'female' THEN 'Female' WHEN 'f' THEN 'Female'
                  WHEN 'other' THEN 'Other'
                  ELSE NULL END;

    v_stage := lower(btrim(COALESCE(v_item.item->>'stage', '')));
    IF v_stage NOT IN ('lead', 'registered', 'trial_completed', 'dropped', 'no_contact') THEN
      v_stage := 'lead';
    END IF;

    -- Resolve (or create) the parent/guardian contact.
    v_contact := NULL;
    IF v_pemail IS NOT NULL THEN
      SELECT id INTO v_contact FROM public.crm_contacts WHERE lower(email) = v_pemail;
      IF v_contact IS NULL THEN
        INSERT INTO public.crm_contacts (
          full_name, last_name, email, phone, street_address, city, zip_code,
          emergency_contact_name, emergency_contact_phone, created_by
        )
        VALUES (
          COALESCE(v_pname, ''), v_plast, v_pemail, v_pphone, v_street, v_city, v_zip,
          v_ecname, v_ecphone, v_coach
        )
        RETURNING id INTO v_contact;
        v_contacts := v_contacts + 1;
      ELSE
        UPDATE public.crm_contacts
        SET full_name  = CASE WHEN btrim(full_name) = '' THEN COALESCE(v_pname, '') ELSE full_name END,
            last_name  = COALESCE(last_name, v_plast),
            phone      = COALESCE(phone, v_pphone),
            street_address          = COALESCE(street_address, v_street),
            city                    = COALESCE(city, v_city),
            zip_code                = COALESCE(zip_code, v_zip),
            emergency_contact_name  = COALESCE(emergency_contact_name, v_ecname),
            emergency_contact_phone = COALESCE(emergency_contact_phone, v_ecphone)
        WHERE id = v_contact;
      END IF;
    ELSIF v_pname IS NOT NULL OR v_plast IS NOT NULL OR v_pphone IS NOT NULL THEN
      SELECT id INTO v_contact
      FROM public.crm_contacts
      WHERE email IS NULL
        AND lower(btrim(full_name)) = lower(COALESCE(v_pname, ''))
        AND COALESCE(phone, '') = COALESCE(v_pphone, '')
      LIMIT 1;
      IF v_contact IS NULL THEN
        INSERT INTO public.crm_contacts (
          full_name, last_name, phone, street_address, city, zip_code,
          emergency_contact_name, emergency_contact_phone, created_by
        )
        VALUES (
          COALESCE(v_pname, ''), v_plast, v_pphone, v_street, v_city, v_zip,
          v_ecname, v_ecphone, v_coach
        )
        RETURNING id INTO v_contact;
        v_contacts := v_contacts + 1;
      END IF;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.crm_leads l
      WHERE l.contact_id IS NOT DISTINCT FROM v_contact
        AND lower(l.first_name) = lower(v_first)
        AND lower(COALESCE(l.last_name, '')) = lower(COALESCE(v_last, ''))
    ) THEN
      v_skipped  := v_skipped + 1;
      v_skiplist := v_skiplist || jsonb_build_object('row', v_item.idx, 'reason', 'Duplicate lead');
      CONTINUE;
    END IF;

    INSERT INTO public.crm_leads (
      contact_id, first_name, last_name, date_of_birth, gender,
      stage, source, campaign, notes, created_by,
      signed_up_at, school_district, graduation_year, allergies_medical,
      prior_diving_experience, prior_gymnastics_experience, diving_location,
      aau_number, participates_in_competitions
    )
    VALUES (
      v_contact, v_first, v_last, v_dob, v_gender,
      v_stage,
      COALESCE(NULLIF(btrim(COALESCE(v_item.item->>'source', '')), ''), NULLIF(btrim(COALESCE(p_default_source, '')), '')),
      COALESCE(NULLIF(btrim(COALESCE(v_item.item->>'campaign', '')), ''), NULLIF(btrim(COALESCE(p_default_campaign, '')), '')),
      NULLIF(btrim(COALESCE(v_item.item->>'notes', '')), ''),
      v_coach,
      v_signup,
      NULLIF(btrim(COALESCE(v_item.item->>'school_district', '')), ''),
      v_gradyear,
      NULLIF(btrim(COALESCE(v_item.item->>'allergies_medical', '')), ''),
      NULLIF(btrim(COALESCE(v_item.item->>'prior_diving_experience', '')), ''),
      NULLIF(btrim(COALESCE(v_item.item->>'prior_gymnastics_experience', '')), ''),
      NULLIF(btrim(COALESCE(v_item.item->>'diving_location', '')), ''),
      NULLIF(btrim(COALESCE(v_item.item->>'aau_number', '')), ''),
      v_comp
    )
    RETURNING id INTO v_lead;

    v_inserted := v_inserted + 1;
    v_ids      := v_ids || to_jsonb(v_lead);
  END LOOP;

  RETURN jsonb_build_object(
    'inserted',         v_inserted,
    'skipped',          v_skipped,
    'contacts_created', v_contacts,
    'lead_ids',         v_ids,
    'skipped_rows',     v_skiplist
  );
END;
$$;


-- Same as v53 except the diver profile no longer receives an email or phone
-- from the lead (they were the dropped diver_email / diver_phone columns).
-- Address, emergency contact, allergies and the other new fields are NOT
-- copied to the profile, matching the rule for CRM notes.
CREATE OR REPLACE FUNCTION public.crm_convert_lead_to_diver(
  p_lead_id          UUID,
  p_current_level    INTEGER DEFAULT 0,
  p_assigned_coach_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_coach_id    UUID := public.crm_current_coach_id();
  v_lead        public.crm_leads%ROWTYPE;
  v_contact     public.crm_contacts%ROWTYPE;
  v_roster_coach UUID;
  v_coach_name  TEXT;
  v_profile_id  UUID;
BEGIN
  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'Only active coaches can do this';
  END IF;

  IF p_current_level IS NOT NULL AND (p_current_level < 0 OR p_current_level > 12) THEN
    RAISE EXCEPTION 'Level must be between 0 and 12';
  END IF;

  SELECT * INTO v_lead FROM public.crm_leads WHERE id = p_lead_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lead not found';
  END IF;
  IF v_lead.converted_diver_id IS NOT NULL THEN
    RAISE EXCEPTION 'This lead has already been converted to a diver';
  END IF;

  IF v_lead.contact_id IS NOT NULL THEN
    SELECT * INTO v_contact FROM public.crm_contacts WHERE id = v_lead.contact_id;
  END IF;

  v_roster_coach := COALESCE(p_assigned_coach_id, v_lead.assigned_coach_id, v_coach_id);

  SELECT full_name INTO v_coach_name
  FROM public.profiles
  WHERE id = v_roster_coach
    AND role IN ('coach', 'super_user')
    AND status = 'active';
  IF v_coach_name IS NULL THEN
    RAISE EXCEPTION 'Selected coach is not valid';
  END IF;

  INSERT INTO public.profiles (
    first_name, last_name, role, status,
    date_of_birth, current_level,
    parent_guardian_name, parent_email, parent_phone,
    created_by_coach_id, gender, assigned_coach_name, start_date
  )
  VALUES (
    v_lead.first_name,
    v_lead.last_name,
    'diver',
    'unclaimed',
    v_lead.date_of_birth,
    p_current_level,
    NULLIF(btrim(COALESCE(v_contact.full_name, '')), ''),
    v_contact.email,
    v_contact.phone,
    v_coach_id,
    v_lead.gender,
    v_coach_name,
    CURRENT_DATE
  )
  RETURNING id INTO v_profile_id;

  INSERT INTO public.roster (coach_id, diver_id) VALUES (v_roster_coach, v_profile_id);

  UPDATE public.crm_leads
  SET converted_diver_id = v_profile_id,
      converted_at       = NOW(),
      assigned_coach_id  = v_roster_coach,
      stage              = 'member'
  WHERE id = p_lead_id;

  INSERT INTO public.crm_activities (lead_id, kind, body, created_by)
  VALUES (p_lead_id, 'other', 'Converted to a DivePractice diver profile', v_coach_id);

  RETURN v_profile_id;
END;
$$;

REVOKE ALL ON FUNCTION public.crm_import_leads(JSONB, TEXT, TEXT)           FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.crm_convert_lead_to_diver(UUID, INTEGER, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.crm_import_leads(JSONB, TEXT, TEXT)           TO authenticated;
GRANT EXECUTE ON FUNCTION public.crm_convert_lead_to_diver(UUID, INTEGER, UUID) TO authenticated;


-- =============================================
-- 3. DROP THE DIVER EMAIL / PHONE COLUMNS
-- =============================================

ALTER TABLE public.crm_leads
  DROP COLUMN IF EXISTS diver_email,
  DROP COLUMN IF EXISTS diver_phone;
