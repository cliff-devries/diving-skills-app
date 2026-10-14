-- ============================================================
-- Migration v71 — retire the private follow-up form
-- Run once in the Supabase SQL editor (paste this file's text, not a .patch).
-- Safe to re-run. Deploy the matching code first or together.
--
-- Everything is now collected on the one public sign-up form (v69/v70), so the
-- per-contact follow-up link is gone:
--   * crm_followup_link / crm_followup_get / crm_followup_submit /
--     crm_followup_token are dropped, and so is crm_leads.followup_token.
--   * crm_email_vars and crm_email_prepare no longer mention the token.
--   * The two "Information & Registration" emails point families to
--     https://divedrills.com/signup instead of a private link (only the step-2
--     paragraph is replaced, so your other edits are kept). A template of
--     yours that still has {{followup_link}} keeps working: it now fills in
--     the sign-up form address.
-- Signed releases already on file (crm_consents, crm_leads.release_signed_*)
-- are untouched. A diver who submits the sign-up form again (same parent email
-- and diver name) is matched to their existing contact and registered.
-- ============================================================

CREATE OR REPLACE FUNCTION public.crm_email_vars(p_lead_id UUID)
RETURNS JSONB
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT jsonb_build_object(
    'lead_id',           l.id,
    'to_email',          NULLIF(btrim(COALESCE(c.email, '')), ''),
    'do_not_contact',    COALESCE(c.do_not_contact, FALSE),
    'parent_first_name', COALESCE(NULLIF(split_part(btrim(COALESCE(c.full_name, '')), ' ', 1), ''), 'there'),
    'parent_name',       COALESCE(NULLIF(btrim(
                           CASE WHEN c.last_name IS NOT NULL AND position(lower(c.last_name) IN lower(COALESCE(c.full_name, ''))) = 0
                                THEN COALESCE(c.full_name, '') || ' ' || c.last_name
                                ELSE COALESCE(c.full_name, '') END), ''), 'there'),
    'diver_first_name',  COALESCE(NULLIF(btrim(COALESCE(l.first_name, '')), ''), 'your diver'),
    'diver_name',        COALESCE(NULLIF(btrim(COALESCE(l.first_name, '') || ' ' || COALESCE(l.last_name, '')), ''), 'your diver'),
    'diving_location',   COALESCE(l.diving_location, ''),
    'trial_date',        COALESCE(to_char(l.trial_date, 'FMDay, FMMonth FMDD'), '')
  )
  FROM public.crm_leads l
  LEFT JOIN public.crm_contacts c ON c.id = l.contact_id
  WHERE l.id = p_lead_id;
$$;
REVOKE ALL ON FUNCTION public.crm_email_vars(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.crm_email_prepare(p_template_id UUID, p_lead_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t      public.crm_email_templates%ROWTYPE;
  v_vars   JSONB := '{}'::jsonb;
  v_coach  UUID := public.crm_current_coach_id();
BEGIN
  IF NOT public.crm_is_coach() THEN
    RAISE EXCEPTION 'Only active coaches can do this';
  END IF;

  SELECT * INTO v_t FROM public.crm_email_templates WHERE id = p_template_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Template not found';
  END IF;

  IF p_lead_id IS NOT NULL THEN
    v_vars := public.crm_email_vars(p_lead_id);
    IF v_vars IS NULL THEN
      RAISE EXCEPTION 'Lead not found';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'coach_id',    v_coach,
    'coach_email', (SELECT email FROM public.profiles WHERE id = v_coach),
    'template',    jsonb_build_object('id', v_t.id, 'name', v_t.name, 'subject', v_t.subject, 'body', v_t.body),
    'vars',        v_vars
  );
END;
$$;
REVOKE ALL ON FUNCTION public.crm_email_prepare(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.crm_email_prepare(UUID, UUID) TO authenticated;

DROP FUNCTION IF EXISTS public.crm_followup_link(UUID);
DROP FUNCTION IF EXISTS public.crm_followup_get(TEXT);
DROP FUNCTION IF EXISTS public.crm_followup_submit(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.crm_followup_token(UUID);
DROP INDEX IF EXISTS public.idx_crm_leads_followup_token;
ALTER TABLE public.crm_leads DROP COLUMN IF EXISTS followup_token;

UPDATE public.crm_email_templates
SET body = replace(body, $o$2. Complete the Upstate Diving registration. Use your private link to enter {{diver_first_name}}'s AAU ID number and sign the photo release, accident waiver and release of liability (it takes about two minutes):
{{followup_link}}$o$, $n$2. Complete the Upstate Diving sign-up form. It includes {{diver_first_name}}'s AAU ID number and the photo release, accident waiver and release of liability:
https://divedrills.com/signup$n$)
WHERE name IN ('1 Information - Registration (RIT)', '1 Canandaigua - Information & Registration');
