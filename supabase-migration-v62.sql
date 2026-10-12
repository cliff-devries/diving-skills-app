-- ============================================================
-- Migration v62 — follow-up form moves the contact to Registered
-- Run once in the Supabase SQL editor (paste this file's text, not a .patch).
-- Safe to re-run. Requires v61.
--
-- Once a contact has BOTH an AAU membership number and a signed photo
-- release & waiver (whichever order they arrive in), crm_followup_submit
-- moves a contact still at the Lead stage to Registered. Contacts already
-- past Lead (Trial Completed, Member, ...) or Dropped / No Contact are left
-- where they are. The move shows in Stage History automatically and the
-- timeline note reads "Follow-up form: ...; moved to Registered".
-- ============================================================

-- Server only: save the AAU number and/or the signed release.
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
BEGIN
  IF p_token IS NULL OR length(p_token) < 32 THEN
    RETURN jsonb_build_object('found', FALSE);
  END IF;

  SELECT * INTO v_lead FROM public.crm_leads WHERE followup_token = p_token FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('found', FALSE);
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
  IF v_lead.stage = 'lead'
     AND v_lead.release_signed_at IS NOT NULL
     AND btrim(COALESCE(v_lead.aau_number, '')) <> '' THEN
    UPDATE public.crm_leads SET stage = 'registered' WHERE id = v_lead.id;
    v_notes := v_notes || 'moved to Registered'::text;
  END IF;

  IF array_length(v_notes, 1) IS NOT NULL THEN
    INSERT INTO public.crm_activities (lead_id, kind, body)
    VALUES (v_lead.id, 'other', 'Follow-up form: ' || array_to_string(v_notes, '; '));
  END IF;

  RETURN jsonb_build_object('found', TRUE, 'ok', TRUE, 'signed', v_signed);
END;
$$;

REVOKE ALL ON FUNCTION public.crm_followup_submit(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crm_followup_submit(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;
