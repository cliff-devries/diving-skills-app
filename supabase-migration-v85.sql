-- ============================================================
-- Migration v85 — fix crm_public_signup to overwrite blank fields on repeat submissions
-- Run once in the Supabase SQL editor.
-- Safe to re-run. Requires v70.
--
-- Bug fixed: the contact and lead UPDATE used COALESCE(existing, new), which
-- treats an existing empty string as "already has data" and silently drops the
-- new value. A parent who submitted incomplete info the first time would never
-- get their data completed by a second submission — the second submission added
-- a timeline note but left all the blank fields blank.
--
-- Fix: use COALESCE(NULLIF(btrim(existing),''), new) so that blank or
-- whitespace-only values are treated as missing and overwritten by the new one.
-- This applies to both the crm_contacts row and the crm_leads row.
--
-- Also fills in diver detail fields (DOB, gender, school district, graduation
-- year, allergies, experience, diving location, competition interest) on a
-- repeat submission — previously only AAU and release were updated.
-- ============================================================

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
  v_aau       TEXT;
  v_stage_before TEXT;
  v_was_signed BOOLEAN;
  v_name      TEXT;
  v_ver       TEXT;
  v_text      TEXT;
  v_moved     BOOLEAN;
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
  v_aau    := public.crm_clip(p->>'aau_number', 60);
  v_name   := public.crm_clip(p->>'signed_name', 160);
  v_ver    := public.crm_clip(p->>'release_version', 60);
  v_text   := public.crm_clip(p->>'release_text', 20000);

  IF v_first IS NULL OR v_last IS NULL OR v_pfirst IS NULL OR v_plast IS NULL
     OR v_aau IS NULL OR v_name IS NULL OR char_length(v_name) < 2 OR v_ver IS NULL OR v_text IS NULL OR v_email IS NULL OR v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' THEN
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
    -- Overwrite blank/whitespace fields with the new submission's values.
    -- COALESCE(NULLIF(btrim(existing),''), new) treats '' the same as NULL
    -- so a second complete submission fills in what the first one left empty.
    UPDATE public.crm_contacts
    SET full_name               = COALESCE(NULLIF(btrim(COALESCE(full_name, '')), ''), v_pfirst),
        last_name               = COALESCE(NULLIF(btrim(COALESCE(last_name, '')), ''), v_plast),
        phone                   = COALESCE(NULLIF(btrim(COALESCE(phone, '')), ''), v_phone),
        street_address          = COALESCE(NULLIF(btrim(COALESCE(street_address, '')), ''), public.crm_clip(p->>'street_address', 200)),
        city                    = COALESCE(NULLIF(btrim(COALESCE(city, '')), ''), public.crm_clip(p->>'city', 100)),
        zip_code                = COALESCE(NULLIF(btrim(COALESCE(zip_code, '')), ''), public.crm_clip(p->>'zip_code', 20)),
        emergency_contact_name  = COALESCE(NULLIF(btrim(COALESCE(emergency_contact_name, '')), ''), public.crm_clip(p->>'emergency_contact_name', 160)),
        emergency_contact_phone = COALESCE(NULLIF(btrim(COALESCE(emergency_contact_phone, '')), ''), public.crm_clip(p->>'emergency_contact_phone', 40))
    WHERE id = v_contact;
  END IF;

  SELECT id, stage, release_signed_at IS NOT NULL INTO v_lead, v_stage_before, v_was_signed
  FROM public.crm_leads
  WHERE contact_id = v_contact
    AND lower(first_name) = lower(v_first)
    AND lower(COALESCE(last_name, '')) = lower(v_last)
  LIMIT 1;

  IF v_lead IS NOT NULL THEN
    -- Update the lead: fill in any fields that were blank on the original submission.
    UPDATE public.crm_leads
    SET date_of_birth           = COALESCE(date_of_birth, v_dob),
        gender                  = COALESCE(NULLIF(btrim(COALESCE(gender, '')), ''), v_gender),
        school_district         = COALESCE(NULLIF(btrim(COALESCE(school_district, '')), ''), public.crm_clip(p->>'school_district', 160)),
        graduation_year         = COALESCE(graduation_year, v_grad),
        allergies_medical       = COALESCE(NULLIF(btrim(COALESCE(allergies_medical, '')), ''), public.crm_clip(p->>'allergies_medical', 2000)),
        prior_diving_experience     = COALESCE(NULLIF(btrim(COALESCE(prior_diving_experience, '')), ''), public.crm_clip(p->>'prior_diving_experience', 2000)),
        prior_gymnastics_experience = COALESCE(NULLIF(btrim(COALESCE(prior_gymnastics_experience, '')), ''), public.crm_clip(p->>'prior_gymnastics_experience', 2000)),
        diving_location         = COALESCE(NULLIF(btrim(COALESCE(diving_location, '')), ''), public.crm_clip(p->>'diving_location', 160)),
        participates_in_competitions = COALESCE(NULLIF(btrim(COALESCE(participates_in_competitions, '')), ''), v_comp),
        referred_by             = COALESCE(NULLIF(btrim(COALESCE(referred_by, '')), ''), public.crm_clip(p->>'referred_by', 160)),
        aau_number              = COALESCE(NULLIF(btrim(COALESCE(aau_number, '')), ''), v_aau),
        release_signed_at       = COALESCE(release_signed_at, NOW()),
        release_signed_name     = COALESCE(NULLIF(btrim(COALESCE(release_signed_name, '')), ''), v_name),
        stage                   = CASE WHEN stage = 'lead' THEN 'registered' ELSE stage END
    WHERE id = v_lead
    RETURNING (stage = 'registered' AND v_stage_before = 'lead') INTO v_moved;
    IF NOT v_was_signed THEN
      INSERT INTO public.crm_consents (lead_id, version, agreement_text, signed_name, ip_address, user_agent)
      VALUES (v_lead, v_ver, v_text, v_name, public.crm_clip(p->>'ip', 64), public.crm_clip(p->>'ua', 400));
    END IF;
    INSERT INTO public.crm_activities (lead_id, kind, body)
    VALUES (v_lead, 'other', 'Submitted the web sign-up form again (any blank fields updated)');
    RETURN jsonb_build_object('ok', TRUE, 'created', FALSE, 'lead_id', v_lead, 'registered', COALESCE(v_moved, FALSE));
  END IF;

  INSERT INTO public.crm_leads (
    contact_id, first_name, last_name, date_of_birth, gender, stage, source, referred_by,
    signed_up_at, school_district, graduation_year, allergies_medical,
    prior_diving_experience, prior_gymnastics_experience, diving_location,
    aau_number, participates_in_competitions, release_signed_at, release_signed_name
  )
  VALUES (
    v_contact, v_first, v_last, v_dob, v_gender, 'registered',
    COALESCE(public.crm_clip(p->>'source', 100), 'Web Form'),
    public.crm_clip(p->>'referred_by', 160),
    NOW(),
    public.crm_clip(p->>'school_district', 160), v_grad, public.crm_clip(p->>'allergies_medical', 2000),
    public.crm_clip(p->>'prior_diving_experience', 2000), public.crm_clip(p->>'prior_gymnastics_experience', 2000),
    public.crm_clip(p->>'diving_location', 160),
    v_aau, v_comp, NOW(), v_name
  )
  RETURNING id INTO v_lead;

  INSERT INTO public.crm_consents (lead_id, version, agreement_text, signed_name, ip_address, user_agent)
  VALUES (v_lead, v_ver, v_text, v_name, public.crm_clip(p->>'ip', 64), public.crm_clip(p->>'ua', 400));

  INSERT INTO public.crm_activities (lead_id, kind, body)
  VALUES (v_lead, 'other', 'Signed up through the web sign-up form: AAU number given and photo release signed by ' || v_name || ' (Registered)');

  RETURN jsonb_build_object('ok', TRUE, 'created', TRUE, 'lead_id', v_lead, 'registered', TRUE);
END;
$$;

REVOKE ALL ON FUNCTION public.crm_public_signup(JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crm_public_signup(JSONB) TO service_role;
