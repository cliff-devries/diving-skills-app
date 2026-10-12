-- ============================================================
-- Migration v61 — DiveCRM follow-up form (AAU number + photo release & waiver)
-- Run once in the Supabase SQL editor (paste this file's text, not a .patch).
-- Safe to re-run.
--
-- A coach copies a private follow-up link from a contact's page. The family
-- opens it (no login), enters the AAU number and agrees to the combined photo
-- release / accident waiver / release of liability by typing their name.
--
-- crm_leads gains:  followup_token, release_signed_at, release_signed_name
-- crm_consents (new): one row per signed agreement — the EXACT text that was
--   shown, the version label, the typed name, the time, and the signer's IP
--   address and browser, kept as evidence of the signature.
--
-- SECURITY (anon still gets nothing):
--   * crm_followup_link(lead)         — active coaches only (authenticated).
--   * crm_followup_get / _submit      — service_role ONLY; the only caller is
--     netlify/functions/crm-followup.js. The long random token in the link is
--     the only key; get returns the diver's FIRST NAME and whether the
--     release is already signed, nothing else.
--   * crm_consents is readable by coaches, deletable by super users only;
--     rows are written only by crm_followup_submit.
-- ============================================================

ALTER TABLE public.crm_leads
  ADD COLUMN IF NOT EXISTS followup_token      TEXT,
  ADD COLUMN IF NOT EXISTS release_signed_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS release_signed_name TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_leads_followup_token
  ON public.crm_leads (followup_token) WHERE followup_token IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.crm_consents (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id      UUID NOT NULL REFERENCES public.crm_leads(id) ON DELETE CASCADE,
  kind         TEXT NOT NULL DEFAULT 'photo_release_waiver',
  version      TEXT NOT NULL,
  agreement_text TEXT NOT NULL,
  signed_name  TEXT NOT NULL CHECK (btrim(signed_name) <> ''),
  signed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ip_address   TEXT,
  user_agent   TEXT
);
CREATE INDEX IF NOT EXISTS idx_crm_consents_lead ON public.crm_consents (lead_id);

ALTER TABLE public.crm_consents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.crm_consents FROM anon;

DROP POLICY IF EXISTS "crm_consents: coach select" ON public.crm_consents;
DROP POLICY IF EXISTS "crm_consents: super delete" ON public.crm_consents;
CREATE POLICY "crm_consents: coach select" ON public.crm_consents
  FOR SELECT TO authenticated USING (public.crm_is_coach());
CREATE POLICY "crm_consents: super delete" ON public.crm_consents
  FOR DELETE TO authenticated USING (public.crm_is_super());


-- Coach: get (creating it the first time) the private follow-up token.
CREATE OR REPLACE FUNCTION public.crm_followup_link(p_lead_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_token TEXT;
BEGIN
  IF NOT public.crm_is_coach() THEN
    RAISE EXCEPTION 'Only active coaches can do this';
  END IF;

  SELECT followup_token INTO v_token FROM public.crm_leads WHERE id = p_lead_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lead not found';
  END IF;

  IF v_token IS NULL THEN
    v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
    UPDATE public.crm_leads SET followup_token = v_token WHERE id = p_lead_id;
  END IF;

  RETURN v_token;
END;
$$;

REVOKE ALL ON FUNCTION public.crm_followup_link(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.crm_followup_link(UUID) TO authenticated;


-- Server only: what the follow-up page may show for a token.
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
    'release_signed', v_lead.release_signed_at IS NOT NULL
  );
END;
$$;

REVOKE ALL ON FUNCTION public.crm_followup_get(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crm_followup_get(TEXT) TO service_role;


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

  IF array_length(v_notes, 1) IS NOT NULL THEN
    INSERT INTO public.crm_activities (lead_id, kind, body)
    VALUES (v_lead.id, 'other', 'Follow-up form: ' || array_to_string(v_notes, '; '));
  END IF;

  RETURN jsonb_build_object('found', TRUE, 'ok', TRUE, 'signed', v_signed);
END;
$$;

REVOKE ALL ON FUNCTION public.crm_followup_submit(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crm_followup_submit(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO service_role;
