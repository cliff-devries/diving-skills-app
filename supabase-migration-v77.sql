-- ============================================================
-- Migration v77 — editable email footer on crm_email_templates
-- Run once in the Supabase SQL editor. Safe to re-run. Requires v65.
--
-- Adds a nullable `footer` column to crm_email_templates. When NULL the
-- mailer falls back to the hardcoded default footer. Coaches set it in
-- the Emails editor in crm.html.
-- ============================================================

ALTER TABLE public.crm_email_templates
  ADD COLUMN IF NOT EXISTS footer TEXT;


-- Rebuild crm_email_due to include the footer in each row it returns.
CREATE OR REPLACE FUNCTION public.crm_email_due(p_lead_id UUID DEFAULT NULL, p_limit INTEGER DEFAULT 40)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_hour INTEGER := extract(hour FROM (NOW() AT TIME ZONE 'America/New_York'))::INTEGER;
  v_out  JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(public.crm_email_vars(d.lead_id) || jsonb_build_object(
           'template_id', d.template_id, 'template_name', d.name,
           'subject', d.subject, 'body', d.body, 'footer', d.footer)), '[]'::jsonb)
  INTO v_out
  FROM (
    SELECT t.id AS template_id, t.name, t.subject, t.body, t.footer, l.id AS lead_id, due.at AS due_at
    FROM public.crm_email_templates t
    JOIN public.crm_leads l ON TRUE
    CROSS JOIN LATERAL (
      SELECT CASE
        WHEN t.trigger_type = 'signup' AND l.created_by IS NULL THEN l.signed_up_at
        WHEN t.trigger_type = 'stage_entered' AND l.stage = t.trigger_stage THEN
          (SELECT max(h.changed_at) FROM public.crm_stage_history h
            WHERE h.lead_id = l.id AND h.to_stage = t.trigger_stage)
      END AS at
    ) due
    WHERE t.enabled
      AND t.trigger_type IN ('signup', 'stage_entered')
      AND t.enabled_at IS NOT NULL
      AND due.at IS NOT NULL
      AND due.at >= t.enabled_at
      AND due.at + make_interval(mins => t.delay_minutes) <= NOW()
      AND (t.send_after_hour IS NULL OR (v_hour >= t.send_after_hour AND v_hour < 21))
      AND (p_lead_id IS NULL OR l.id = p_lead_id)
      AND NOT EXISTS (
        SELECT 1 FROM public.crm_email_log g
        WHERE g.template_id = t.id AND g.lead_id = l.id AND g.automatic AND g.status IN ('sent', 'skipped'))
      AND (SELECT count(*) FROM public.crm_email_log g
           WHERE g.template_id = t.id AND g.lead_id = l.id AND g.automatic AND g.status = 'failed') < 3
    ORDER BY due.at
    LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 40), 100))
  ) d;
  RETURN v_out;
END;
$$;
REVOKE ALL ON FUNCTION public.crm_email_due(UUID, INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crm_email_due(UUID, INTEGER) TO service_role;


-- Rebuild crm_email_prepare to include footer so crm-send-email.js can pass it.
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
    IF position('{{followup_link}}' IN (v_t.subject || ' ' || v_t.body)) > 0 THEN
      PERFORM public.crm_followup_token(p_lead_id);
    END IF;
    v_vars := public.crm_email_vars(p_lead_id);
    IF v_vars IS NULL THEN
      RAISE EXCEPTION 'Lead not found';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'coach_id',    v_coach,
    'coach_email', (SELECT email FROM public.profiles WHERE id = v_coach),
    'template',    jsonb_build_object('id', v_t.id, 'name', v_t.name,
                     'subject', v_t.subject, 'body', v_t.body, 'footer', v_t.footer),
    'vars',        v_vars
  );
END;
$$;
REVOKE ALL ON FUNCTION public.crm_email_prepare(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.crm_email_prepare(UUID, UUID) TO authenticated;
