-- ============================================================
-- Migration v56 — DiveCRM "Referred by"
-- Run once in the Supabase SQL editor (paste this file's text, not a .patch).
-- Safe to re-run.
--
-- Adds crm_leads.referred_by (free text: who referred the family) and
-- replaces crm_import_leads so the Add Lead form and CSV import can save it
-- (new JSON key: referred_by). The function is the v55 version plus that one
-- key; nothing else about its behaviour changes. Table policies are untouched
-- (v53's explicit policies already cover new columns).
-- ============================================================

ALTER TABLE public.crm_leads ADD COLUMN IF NOT EXISTS referred_by TEXT;

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
      aau_number, participates_in_competitions, referred_by
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
      v_comp,
      NULLIF(btrim(COALESCE(v_item.item->>'referred_by', '')), '')
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

REVOKE ALL ON FUNCTION public.crm_import_leads(JSONB, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.crm_import_leads(JSONB, TEXT, TEXT) TO authenticated;
