-- ============================================================
-- Migration v60 — "Interested in competition?" gets a third answer (Maybe)
-- Run once in the Supabase SQL editor (paste this file's text, not a .patch).
-- Safe to re-run.
--
-- crm_leads.participates_in_competitions was a true/false column, which
-- cannot hold a third answer. It becomes text holding 'yes', 'no' or
-- 'maybe' (NULL = not answered). Existing values convert: true -> 'yes',
-- false -> 'no'. Run this BEFORE (or right as) the matching deploy of
-- crm.html and the sign-up form; the pages save the text values.
--
-- crm_import_leads (from v56) and crm_public_signup (from v59) are
-- replaced because both converted the answer to a boolean; they are
-- otherwise unchanged. Table policies are untouched.
-- ============================================================

ALTER TABLE public.crm_leads
  ALTER COLUMN participates_in_competitions TYPE TEXT
  USING CASE participates_in_competitions::text
          WHEN 'true' THEN 'yes' WHEN 'false' THEN 'no' WHEN 'yes' THEN 'yes'
          WHEN 'no' THEN 'no' WHEN 'maybe' THEN 'maybe' ELSE NULL END;

ALTER TABLE public.crm_leads DROP CONSTRAINT IF EXISTS crm_leads_competition_check;
ALTER TABLE public.crm_leads
  ADD CONSTRAINT crm_leads_competition_check
  CHECK (participates_in_competitions IS NULL OR participates_in_competitions IN ('yes', 'no', 'maybe'));

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
  v_comp      TEXT;
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
                WHEN v_comp_txt IN ('yes', 'y', 'true', 't', '1') THEN 'yes'
                WHEN v_comp_txt IN ('no', 'n', 'false', 'f', '0') THEN 'no'
                WHEN v_comp_txt IN ('maybe', 'unsure', 'not sure', 'not sure yet') THEN 'maybe'
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

CREATE OR REPLACE FUNCTION public.crm_public_signup(p JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_first     TEXT;
  v_last      TEXT;
  v_pfirst    TEXT;
  v_plast     TEXT;
  v_email     TEXT;
  v_phone     TEXT;
  v_dob       DATE;
  v_grad      INTEGER;
  v_comp      TEXT;
  v_gender    TEXT;
  v_contact   UUID;
  v_lead      UUID;
BEGIN
  IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN
    RAISE EXCEPTION 'invalid submission';
  END IF;

  IF (SELECT count(*) FROM public.crm_leads
      WHERE created_by IS NULL AND created_at > NOW() - INTERVAL '10 minutes') >= 60 THEN
    RAISE EXCEPTION 'busy';
  END IF;

  v_first  := public.crm_clip(p->>'first_name', 80);
  v_last   := public.crm_clip(p->>'last_name', 80);
  v_pfirst := public.crm_clip(p->>'parent_first_name', 80);
  v_plast  := public.crm_clip(p->>'parent_last_name', 80);
  v_email  := lower(public.crm_clip(p->>'parent_email', 254));
  v_phone  := public.crm_clip(p->>'parent_phone', 40);

  IF v_first IS NULL OR v_last IS NULL OR v_pfirst IS NULL OR v_plast IS NULL
     OR v_email IS NULL OR v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' THEN
    RAISE EXCEPTION 'invalid submission';
  END IF;

  v_dob := NULL;
  BEGIN
    v_dob := NULLIF(btrim(COALESCE(p->>'date_of_birth', '')), '')::date;
  EXCEPTION WHEN others THEN
    v_dob := NULL;
  END;
  IF v_dob IS NOT NULL AND (v_dob > CURRENT_DATE OR v_dob < DATE '1920-01-01') THEN
    v_dob := NULL;
  END IF;

  v_grad := NULL;
  BEGIN
    v_grad := NULLIF(btrim(COALESCE(p->>'graduation_year', '')), '')::integer;
  EXCEPTION WHEN others THEN
    v_grad := NULL;
  END;
  IF v_grad IS NOT NULL AND (v_grad < 1990 OR v_grad > 2100) THEN
    v_grad := NULL;
  END IF;

  v_comp := CASE lower(btrim(COALESCE(p->>'participates_in_competitions', '')))
              WHEN 'yes' THEN 'yes' WHEN 'no' THEN 'no' WHEN 'maybe' THEN 'maybe' ELSE NULL END;

  v_gender := CASE lower(btrim(COALESCE(p->>'gender', '')))
                WHEN 'male' THEN 'Male' WHEN 'female' THEN 'Female' WHEN 'other' THEN 'Other'
                ELSE NULL END;

  SELECT id INTO v_contact FROM public.crm_contacts WHERE lower(email) = v_email;
  IF v_contact IS NULL THEN
    INSERT INTO public.crm_contacts (
      full_name, last_name, email, phone, street_address, city, zip_code,
      emergency_contact_name, emergency_contact_phone
    )
    VALUES (
      v_pfirst, v_plast, v_email, v_phone,
      public.crm_clip(p->>'street_address', 200), public.crm_clip(p->>'city', 100), public.crm_clip(p->>'zip_code', 20),
      public.crm_clip(p->>'emergency_contact_name', 160), public.crm_clip(p->>'emergency_contact_phone', 40)
    )
    RETURNING id INTO v_contact;
  ELSE
    UPDATE public.crm_contacts
    SET last_name               = COALESCE(last_name, v_plast),
        phone                   = COALESCE(phone, v_phone),
        street_address          = COALESCE(street_address, public.crm_clip(p->>'street_address', 200)),
        city                    = COALESCE(city, public.crm_clip(p->>'city', 100)),
        zip_code                = COALESCE(zip_code, public.crm_clip(p->>'zip_code', 20)),
        emergency_contact_name  = COALESCE(emergency_contact_name, public.crm_clip(p->>'emergency_contact_name', 160)),
        emergency_contact_phone = COALESCE(emergency_contact_phone, public.crm_clip(p->>'emergency_contact_phone', 40))
    WHERE id = v_contact;
  END IF;

  SELECT id INTO v_lead
  FROM public.crm_leads
  WHERE contact_id = v_contact
    AND lower(first_name) = lower(v_first)
    AND lower(COALESCE(last_name, '')) = lower(v_last)
  LIMIT 1;

  IF v_lead IS NOT NULL THEN
    INSERT INTO public.crm_activities (lead_id, kind, body)
    VALUES (v_lead, 'other', 'Submitted the web sign-up form again');
    RETURN jsonb_build_object('ok', TRUE);
  END IF;

  INSERT INTO public.crm_leads (
    contact_id, first_name, last_name, date_of_birth, gender, stage, source, referred_by,
    signed_up_at, school_district, graduation_year, allergies_medical,
    prior_diving_experience, prior_gymnastics_experience, diving_location,
    aau_number, participates_in_competitions
  )
  VALUES (
    v_contact, v_first, v_last, v_dob, v_gender, 'lead',
    COALESCE(public.crm_clip(p->>'source', 100), 'Web Form'),
    public.crm_clip(p->>'referred_by', 160),
    NOW(),
    public.crm_clip(p->>'school_district', 160), v_grad, public.crm_clip(p->>'allergies_medical', 2000),
    public.crm_clip(p->>'prior_diving_experience', 2000), public.crm_clip(p->>'prior_gymnastics_experience', 2000),
    public.crm_clip(p->>'diving_location', 160),
    public.crm_clip(p->>'aau_number', 60), v_comp
  )
  RETURNING id INTO v_lead;

  INSERT INTO public.crm_activities (lead_id, kind, body)
  VALUES (v_lead, 'other', 'Signed up through the web sign-up form');

  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

REVOKE ALL ON FUNCTION public.crm_import_leads(JSONB, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.crm_import_leads(JSONB, TEXT, TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.crm_public_signup(JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crm_public_signup(JSONB) TO service_role;
