-- ============================================================
-- Migration v63 — AAU number from ANY source counts
-- Run once in the Supabase SQL editor (paste this file's text, not a .patch).
-- Safe to re-run. Requires v61 and v62.
--
-- The AAU number is required before a contact can be Registered, but it does
-- not matter who entered it. Now:
--   * crm_followup_get also reports has_aau (a yes/no only, never the number),
--     so the follow-up form only demands the number when none is on file.
--   * crm_followup_submit refuses a submission only when neither the family
--     nor the CRM already has an AAU number.
--   * A trigger moves a contact still at Lead to Registered whenever it
--     ends up with both an AAU number and a signed release — including when a
--     coach types the number into the CRM after the family signed.
--     (The stage move is logged in Stage History like any other.)
-- ============================================================

CREATE OR REPLACE FUNCTION public.crm_followup_get(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_lead public.crm_leads%ROWTYPE;
BEGIN
  IF p_token IS NULL OR length(p_token) < 32 THEN
    RETURN jsonb_build_object('found', FALSE);
  END IF;

  SELECT * INTO v_lead FROM public.crm_leads WHERE followup_token = p_token;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('found', FALSE);
  END IF;

  RETURN jsonb_build_object(
    'found', TRUE,
    'first_name', v_lead.first_name,
    'release_signed', v_lead.release_signed_at IS NOT NULL,
    'has_aau', btrim(COALESCE(v_lead.aau_number, '')) <> ''
  );
END;
$$;

REVOKE ALL ON FUNCTION public.crm_followup_get(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crm_followup_get(TEXT) TO service_role;


CREATE OR REPLACE FUNCTION public.crm_leads_auto_register()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.stage = 'lead'
     AND NEW.release_signed_at IS NOT NULL
     AND btrim(COALESCE(NEW.aau_number, '')) <> '' THEN
    UPDATE public.crm_leads SET stage = 'registered' WHERE id = NEW.id AND stage = 'lead';
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS crm_leads_auto_register ON public.crm_leads;
CREATE TRIGGER crm_leads_auto_register
  AFTER UPDATE OF aau_number, release_signed_at ON public.crm_leads
  FOR EACH ROW EXECUTE FUNCTION public.crm_leads_auto_register();


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

  RETURN jsonb_build_object('found', TRUE, 'ok', TRUE, 'signed', v_signed);
END;
$$;

REVOKE ALL ON FUNCTION public.crm_followup_submit(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crm_followup_submit(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;
