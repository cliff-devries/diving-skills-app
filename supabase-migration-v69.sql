-- ============================================================
-- Migration v69 — the public sign-up form collects the AAU number and
-- registers the diver on the spot
-- Run once in the Supabase SQL editor (paste this file's text, not a .patch).
-- Safe to re-run. Deploy the matching signup.html / crm-signup.js together.
--
-- crm_public_signup (v64) now:
--   * requires an AAU number;
--   * creates the contact at "Registered" (not "Lead"). Leads added by hand
--     or imported stay in the Lead pool until they sign up;
--   * for a repeat submission of a diver who is still a Lead, saves the AAU
--     number (if none on file) and moves them to Registered.
-- The photo release / waiver is still signed through the private follow-up
-- link; it no longer gates Registered for web sign-ups.
-- The "Sign-up confirmation" email is reworded to match, but only while it is
-- still exactly the text v65 loaded (your edits are never overwritten).
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

  IF v_first IS NULL OR v_last IS NULL OR v_pfirst IS NULL OR v_plast IS NULL
     OR v_aau IS NULL OR v_email IS NULL OR v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' THEN
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

  SELECT id, stage INTO v_lead, v_stage_before
  FROM public.crm_leads
  WHERE contact_id = v_contact
    AND lower(first_name) = lower(v_first)
    AND lower(COALESCE(last_name, '')) = lower(v_last)
  LIMIT 1;

  IF v_lead IS NOT NULL THEN
    UPDATE public.crm_leads
    SET aau_number = COALESCE(NULLIF(btrim(COALESCE(aau_number, '')), ''), v_aau),
        stage      = CASE WHEN stage = 'lead' THEN 'registered' ELSE stage END
    WHERE id = v_lead
    RETURNING (stage = 'registered' AND v_stage_before = 'lead') INTO v_moved;
    INSERT INTO public.crm_activities (lead_id, kind, body)
    VALUES (v_lead, 'other', 'Submitted the web sign-up form again');
    RETURN jsonb_build_object('ok', TRUE, 'created', FALSE, 'lead_id', v_lead, 'registered', COALESCE(v_moved, FALSE));
  END IF;

  INSERT INTO public.crm_leads (
    contact_id, first_name, last_name, date_of_birth, gender, stage, source, referred_by,
    signed_up_at, school_district, graduation_year, allergies_medical,
    prior_diving_experience, prior_gymnastics_experience, diving_location,
    aau_number, participates_in_competitions
  )
  VALUES (
    v_contact, v_first, v_last, v_dob, v_gender, 'registered',
    COALESCE(public.crm_clip(p->>'source', 100), 'Web Form'),
    public.crm_clip(p->>'referred_by', 160),
    NOW(),
    public.crm_clip(p->>'school_district', 160), v_grad, public.crm_clip(p->>'allergies_medical', 2000),
    public.crm_clip(p->>'prior_diving_experience', 2000), public.crm_clip(p->>'prior_gymnastics_experience', 2000),
    public.crm_clip(p->>'diving_location', 160),
    v_aau, v_comp
  )
  RETURNING id INTO v_lead;

  INSERT INTO public.crm_activities (lead_id, kind, body)
  VALUES (v_lead, 'other', 'Signed up through the web sign-up form with an AAU number (Registered)');

  RETURN jsonb_build_object('ok', TRUE, 'created', TRUE, 'lead_id', v_lead, 'registered', TRUE);
END;
$$;

REVOKE ALL ON FUNCTION public.crm_public_signup(JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crm_public_signup(JSONB) TO service_role;

UPDATE public.crm_email_templates
SET body = $t$Hi {{parent_first_name}},

Thank you for signing up {{diver_first_name}} with Upstate Diving! We have received your information, and an Upstate Diving coordinator will follow up soon to confirm the best class, location, and time.

{{diver_first_name}} is now registered. There is one more short step before the first practice: please sign our photo release and accident waiver:
{{followup_link}}

If you have any questions, just reply to this email.

Thank you,
Upstate Diving$t$
WHERE name = 'Sign-up confirmation' AND body = $o$Hi {{parent_first_name}},

Thank you for signing up {{diver_first_name}} with Upstate Diving! We have received your information, and an Upstate Diving coordinator will follow up soon to confirm the best class, location, and time.

To finish registration, please complete one more short step: enter {{diver_first_name}}'s AAU membership number and sign our photo release and accident waiver. Divers cannot be on the pool deck without an AAU membership number.

Complete your registration: {{followup_link}}

If you have any questions, just reply to this email.

Thank you,
Upstate Diving$o$;
