-- ============================================================
-- Migration v64 — facts the notification emails need
-- Run once in the Supabase SQL editor (paste this file's text, not a .patch).
-- Safe to re-run. Requires v59-v63.
--
-- Both RPCs are service_role-only and called only by the Netlify functions
-- crm-signup.js and crm-followup.js, which email the coach.
--   crm_public_signup   now also returns { created, lead_id }, so a repeat
--                       submission (created = false) sends no "new sign-up" email.
--   crm_followup_submit now also returns { registered, lead_id, diver_name,
--                       parent_name, parent_email, parent_phone }; registered is
--                       true only when THIS submission moved the contact from
--                       Lead to Registered.
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
    RETURN jsonb_build_object('ok', TRUE, 'created', FALSE, 'lead_id', v_lead);
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

  RETURN jsonb_build_object('ok', TRUE, 'created', TRUE, 'lead_id', v_lead);
END;
$$;


REVOKE ALL ON FUNCTION public.crm_public_signup(JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crm_public_signup(JSONB) TO service_role;

CREATE OR REPLACE FUNCTION public.crm_followup_submit(
  p_token       TEXT,
  p_aau         TEXT,
  p_signed_name TEXT,
  p_version     TEXT,
  p_text        TEXT,
  p_ip          TEXT,
  p_ua          TEXT
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_lead   public.crm_leads%ROWTYPE;
  v_aau    TEXT := public.crm_clip(p_aau, 60);
  v_name   TEXT := public.crm_clip(p_signed_name, 160);
  v_notes  TEXT[] := ARRAY[]::TEXT[];
  v_signed BOOLEAN := FALSE;
  v_before TEXT;
BEGIN
  IF p_token IS NULL OR length(p_token) < 32 THEN
    RETURN jsonb_build_object('found', FALSE);
  END IF;

  SELECT * INTO v_lead FROM public.crm_leads WHERE followup_token = p_token FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('found', FALSE);
  END IF;

  v_before := v_lead.stage;
  IF v_aau IS NULL AND btrim(COALESCE(v_lead.aau_number, '')) = '' THEN
    RETURN jsonb_build_object('found', TRUE, 'ok', FALSE, 'error', 'aau_required');
  END IF;

  IF v_name IS NOT NULL THEN
    IF char_length(v_name) < 2 OR public.crm_clip(p_text, 20000) IS NULL OR public.crm_clip(p_version, 60) IS NULL THEN
      RAISE EXCEPTION 'invalid submission';
    END IF;
    IF v_lead.release_signed_at IS NULL THEN
      INSERT INTO public.crm_consents (lead_id, version, agreement_text, signed_name, ip_address, user_agent)
      VALUES (v_lead.id, public.crm_clip(p_version, 60), p_text, v_name,
              public.crm_clip(p_ip, 64), public.crm_clip(p_ua, 400));
      UPDATE public.crm_leads
      SET release_signed_at = NOW(), release_signed_name = v_name
      WHERE id = v_lead.id;
      v_signed := TRUE;
      v_notes := v_notes || ('Photo release & waiver signed by ' || v_name);
    END IF;
  END IF;

  IF v_aau IS NOT NULL AND v_aau IS DISTINCT FROM v_lead.aau_number THEN
    UPDATE public.crm_leads SET aau_number = v_aau WHERE id = v_lead.id;
    v_notes := v_notes || ('AAU membership number entered: ' || v_aau);
  END IF;

  SELECT * INTO v_lead FROM public.crm_leads WHERE id = v_lead.id;
  IF v_before = 'lead' AND v_lead.stage = 'registered' THEN
    v_notes := v_notes || 'moved to Registered'::text;
  END IF;

  IF array_length(v_notes, 1) IS NOT NULL THEN
    INSERT INTO public.crm_activities (lead_id, kind, body)
    VALUES (v_lead.id, 'other', 'Follow-up form: ' || array_to_string(v_notes, '; '));
  END IF;

  RETURN jsonb_build_object(
    'found', TRUE, 'ok', TRUE, 'signed', v_signed,
    'registered', (v_before = 'lead' AND v_lead.stage = 'registered'),
    'lead_id', v_lead.id,
    'diver_name', btrim(v_lead.first_name || ' ' || COALESCE(v_lead.last_name, '')),
    'parent_name', (SELECT btrim(COALESCE(full_name, '') || ' ' || COALESCE(last_name, '')) FROM public.crm_contacts WHERE id = v_lead.contact_id),
    'parent_email', (SELECT email FROM public.crm_contacts WHERE id = v_lead.contact_id),
    'parent_phone', (SELECT phone FROM public.crm_contacts WHERE id = v_lead.contact_id)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.crm_followup_submit(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crm_followup_submit(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;
