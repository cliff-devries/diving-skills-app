-- ============================================================
-- Migration v65 — DiveCRM email templates, triggers and send log
-- Run once in the Supabase SQL editor (paste this file's text, not a .patch).
-- Safe to re-run. Requires v53-v64.
--
-- crm_email_templates  Pre-written emails a coach edits in the CRM "Emails" tab.
--   trigger_type  'manual'        only sent by hand from a contact's page
--                 'signup'        sent after the public sign-up form is submitted
--                 'stage_entered' sent after a contact has been in trigger_stage
--                                 for delay_minutes (and is still in it)
--   delay_minutes how long to wait (0 = right away)
--   send_after_hour  optional, 0-20: only send between that hour and 9pm
--                 Eastern (emails that come due overnight go out next morning)
--   enabled_at    set whenever a trigger is switched on or changed. An email
--                 only fires for events AFTER this moment, so turning one on
--                 never mails the contacts who are already in the CRM.
-- crm_email_log        One row per send / skip / failure. For automatic emails
--   a unique index guarantees one email per template per contact, ever.
--
-- SECURITY: coaches manage templates and read the log through RLS. Sending
-- happens only in Netlify functions: crm_email_due / crm_email_record /
-- crm_followup_token are service_role ONLY; crm_email_prepare is coach-only.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.crm_email_templates (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT NOT NULL CHECK (btrim(name) <> ''),
  subject         TEXT NOT NULL CHECK (btrim(subject) <> ''),
  body            TEXT NOT NULL CHECK (btrim(body) <> ''),
  trigger_type    TEXT NOT NULL DEFAULT 'manual'
                    CHECK (trigger_type IN ('manual', 'signup', 'stage_entered')),
  trigger_stage   TEXT CHECK (trigger_stage IS NULL OR trigger_stage IN
                    ('lead', 'registered', 'trial_completed', 'member', 'graduated', 'dropped', 'no_contact')),
  delay_minutes   INTEGER NOT NULL DEFAULT 0 CHECK (delay_minutes BETWEEN 0 AND 525600),
  send_after_hour INTEGER CHECK (send_after_hour IS NULL OR send_after_hour BETWEEN 0 AND 20),
  enabled         BOOLEAN NOT NULL DEFAULT FALSE,
  enabled_at      TIMESTAMPTZ,
  sort_order      INTEGER NOT NULL DEFAULT 0,
  created_by      UUID,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (trigger_type <> 'stage_entered' OR trigger_stage IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS public.crm_email_log (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id   UUID REFERENCES public.crm_email_templates(id) ON DELETE SET NULL,
  template_name TEXT,
  lead_id       UUID NOT NULL REFERENCES public.crm_leads(id) ON DELETE CASCADE,
  to_email      TEXT,
  subject       TEXT,
  status        TEXT NOT NULL CHECK (status IN ('sent', 'failed', 'skipped')),
  error         TEXT,
  automatic     BOOLEAN NOT NULL DEFAULT FALSE,
  sent_by       UUID,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_crm_email_log_lead    ON public.crm_email_log (lead_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_crm_email_log_created ON public.crm_email_log (created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_email_log_once
  ON public.crm_email_log (template_id, lead_id)
  WHERE automatic AND status IN ('sent', 'skipped');


CREATE OR REPLACE FUNCTION public.crm_email_templates_before()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_by := COALESCE(NEW.created_by, public.crm_current_coach_id());
  END IF;
  IF NEW.trigger_type <> 'stage_entered' THEN
    NEW.trigger_stage := NULL;
  END IF;
  IF NEW.enabled AND NEW.trigger_type <> 'manual' AND (
       TG_OP = 'INSERT'
       OR NOT OLD.enabled
       OR NEW.trigger_type IS DISTINCT FROM OLD.trigger_type
       OR NEW.trigger_stage IS DISTINCT FROM OLD.trigger_stage
     ) THEN
    NEW.enabled_at := NOW();
  END IF;
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS crm_email_templates_before ON public.crm_email_templates;
CREATE TRIGGER crm_email_templates_before
  BEFORE INSERT OR UPDATE ON public.crm_email_templates
  FOR EACH ROW EXECUTE FUNCTION public.crm_email_templates_before();


ALTER TABLE public.crm_email_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_email_log       ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.crm_email_templates FROM anon;
REVOKE ALL ON public.crm_email_log       FROM anon;

DROP POLICY IF EXISTS "crm_email_templates: coach select" ON public.crm_email_templates;
DROP POLICY IF EXISTS "crm_email_templates: coach insert" ON public.crm_email_templates;
DROP POLICY IF EXISTS "crm_email_templates: coach update" ON public.crm_email_templates;
DROP POLICY IF EXISTS "crm_email_templates: coach delete" ON public.crm_email_templates;
CREATE POLICY "crm_email_templates: coach select" ON public.crm_email_templates
  FOR SELECT TO authenticated USING (public.crm_is_coach());
CREATE POLICY "crm_email_templates: coach insert" ON public.crm_email_templates
  FOR INSERT TO authenticated WITH CHECK (public.crm_is_coach());
CREATE POLICY "crm_email_templates: coach update" ON public.crm_email_templates
  FOR UPDATE TO authenticated USING (public.crm_is_coach()) WITH CHECK (public.crm_is_coach());
CREATE POLICY "crm_email_templates: coach delete" ON public.crm_email_templates
  FOR DELETE TO authenticated USING (public.crm_is_coach());

DROP POLICY IF EXISTS "crm_email_log: coach select" ON public.crm_email_log;
DROP POLICY IF EXISTS "crm_email_log: super delete" ON public.crm_email_log;
CREATE POLICY "crm_email_log: coach select" ON public.crm_email_log
  FOR SELECT TO authenticated USING (public.crm_is_coach());
CREATE POLICY "crm_email_log: super delete" ON public.crm_email_log
  FOR DELETE TO authenticated USING (public.crm_is_super());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_email_templates TO authenticated;
GRANT SELECT, DELETE ON public.crm_email_log TO authenticated;


-- Placeholder values for one contact (internal helper, no direct access).
CREATE OR REPLACE FUNCTION public.crm_email_vars(p_lead_id UUID)
RETURNS JSONB
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT jsonb_build_object(
    'lead_id',           l.id,
    'to_email',          NULLIF(btrim(COALESCE(c.email, '')), ''),
    'do_not_contact',    COALESCE(c.do_not_contact, FALSE),
    'followup_token',    l.followup_token,
    'parent_first_name', COALESCE(NULLIF(split_part(btrim(COALESCE(c.full_name, '')), ' ', 1), ''), 'there'),
    'parent_name',       COALESCE(NULLIF(btrim(
                           CASE WHEN c.last_name IS NOT NULL AND position(lower(c.last_name) IN lower(COALESCE(c.full_name, ''))) = 0
                                THEN COALESCE(c.full_name, '') || ' ' || c.last_name
                                ELSE COALESCE(c.full_name, '') END), ''), 'there'),
    'diver_first_name',  l.first_name,
    'diver_name',        btrim(l.first_name || ' ' || COALESCE(l.last_name, '')),
    'diving_location',   COALESCE(l.diving_location, ''),
    'trial_date',        COALESCE(to_char(l.trial_date, 'FMDay, FMMonth FMDD'), '')
  )
  FROM public.crm_leads l
  LEFT JOIN public.crm_contacts c ON c.id = l.contact_id
  WHERE l.id = p_lead_id;
$$;
REVOKE ALL ON FUNCTION public.crm_email_vars(UUID) FROM PUBLIC, anon, authenticated;


-- Server only: make sure a contact has a follow-up token and return it.
CREATE OR REPLACE FUNCTION public.crm_followup_token(p_lead_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_token TEXT;
BEGIN
  SELECT followup_token INTO v_token FROM public.crm_leads WHERE id = p_lead_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  IF v_token IS NULL THEN
    v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
    UPDATE public.crm_leads SET followup_token = v_token WHERE id = p_lead_id;
  END IF;
  RETURN v_token;
END;
$$;
REVOKE ALL ON FUNCTION public.crm_followup_token(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crm_followup_token(UUID) TO service_role;


-- Server only: automatic emails that are due right now.
CREATE OR REPLACE FUNCTION public.crm_email_due(p_lead_id UUID DEFAULT NULL, p_limit INTEGER DEFAULT 40)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_hour INTEGER := extract(hour FROM (NOW() AT TIME ZONE 'America/New_York'))::INTEGER;
  v_out  JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(public.crm_email_vars(d.lead_id) || jsonb_build_object(
           'template_id', d.template_id, 'template_name', d.name,
           'subject', d.subject, 'body', d.body)), '[]'::jsonb)
  INTO v_out
  FROM (
    SELECT t.id AS template_id, t.name, t.subject, t.body, l.id AS lead_id, due.at AS due_at
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


-- Server only: record what happened to one email.
CREATE OR REPLACE FUNCTION public.crm_email_record(
  p_template_id UUID, p_lead_id UUID, p_to TEXT, p_subject TEXT,
  p_status TEXT, p_error TEXT, p_automatic BOOLEAN, p_sent_by UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_name TEXT;
  v_rows INTEGER;
BEGIN
  IF p_status NOT IN ('sent', 'failed', 'skipped') THEN
    RAISE EXCEPTION 'bad status';
  END IF;
  SELECT name INTO v_name FROM public.crm_email_templates WHERE id = p_template_id;

  INSERT INTO public.crm_email_log
    (template_id, template_name, lead_id, to_email, subject, status, error, automatic, sent_by)
  VALUES
    (p_template_id, v_name, p_lead_id, public.crm_clip(p_to, 254), public.crm_clip(p_subject, 300),
     p_status, public.crm_clip(p_error, 500), COALESCE(p_automatic, FALSE), p_sent_by)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF p_status = 'sent' AND v_rows > 0 THEN
    INSERT INTO public.crm_activities (lead_id, kind, body, created_by)
    VALUES (p_lead_id, 'email',
            'Email sent: ' || COALESCE(v_name, 'email') ||
              CASE WHEN COALESCE(p_automatic, FALSE) THEN ' (automatic)' ELSE '' END,
            p_sent_by);
  END IF;
  RETURN v_rows > 0;
END;
$$;
REVOKE ALL ON FUNCTION public.crm_email_record(UUID, UUID, TEXT, TEXT, TEXT, TEXT, BOOLEAN, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crm_email_record(UUID, UUID, TEXT, TEXT, TEXT, TEXT, BOOLEAN, UUID) TO service_role;


-- Coach only (called with the coach's own login by crm-send-email.js): the
-- template plus, for a contact, the values to fill in. Doubles as the check
-- that the caller really is an active coach.
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
    'template',    jsonb_build_object('id', v_t.id, 'name', v_t.name, 'subject', v_t.subject, 'body', v_t.body),
    'vars',        v_vars
  );
END;
$$;
REVOKE ALL ON FUNCTION public.crm_email_prepare(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.crm_email_prepare(UUID, UUID) TO authenticated;


-- The sign-up confirmation. Switched on, so it applies to sign-ups from now on.
-- Edit the wording any time in the CRM Emails tab.
INSERT INTO public.crm_email_templates
  (name, subject, body, trigger_type, delay_minutes, enabled, sort_order)
SELECT
  'Sign-up confirmation',
  'We received your Upstate Diving sign-up for {{diver_first_name}}',
  $body$Hi {{parent_first_name}},

Thank you for signing up {{diver_first_name}} with Upstate Diving! We have received your information, and an Upstate Diving coordinator will follow up soon to confirm the best class, location, and time.

To finish registration, please complete one more short step: enter {{diver_first_name}}'s AAU membership number and sign our photo release and accident waiver. Divers cannot be on the pool deck without an AAU membership number.

Complete your registration: {{followup_link}}

If you have any questions, just reply to this email.

Thank you,
Upstate Diving$body$,
  'signup', 0, TRUE, 10
WHERE NOT EXISTS (SELECT 1 FROM public.crm_email_templates WHERE name = 'Sign-up confirmation');
