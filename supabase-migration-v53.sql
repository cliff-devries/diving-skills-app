-- ============================================================
-- Migration v53 — Upstate Diving CRM (leads/contacts before they join)
-- Run once in the Supabase SQL editor. Safe to re-run: tables use
-- IF NOT EXISTS, policies/triggers use DROP IF EXISTS, functions use
-- CREATE OR REPLACE.
--
-- WHAT THIS ADDS (all new, prefixed crm_ — no existing table is altered):
--   crm_contacts       parents/guardians (one row per family contact)
--   crm_leads          prospective divers, linked to a contact; carries the
--                      pipeline stage, source, campaign and follow-up date
--   crm_activities     notes / calls / emails / texts logged against a lead
--   crm_stage_history  automatic audit trail of every stage change
--
-- STAGES (crm_leads.stage):
--   lead -> registered -> trial_completed -> member -> graduated
--   plus the exits: dropped (Dropped/Quit) and no_contact (No contact)
--   'member' and 'graduated' can only be reached through
--   crm_convert_lead_to_diver(), which creates the DivePractice diver.
--
-- SECURITY: these tables hold parent contact details for minors. Access is
-- limited to active coaches / super users (same gate as every other
-- club-wide read in this app, see v24). anon gets nothing. Deletes are
-- super-user only. Nothing here is exposed through a public RPC.
-- ============================================================


-- =============================================
-- 1. HELPERS
-- =============================================

CREATE OR REPLACE FUNCTION public.crm_is_coach()
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE auth_user_id = auth.uid()
      AND role IN ('coach', 'super_user')
      AND status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION public.crm_is_super()
RETURNS boolean
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE auth_user_id = auth.uid()
      AND status = 'active'
      AND (role = 'super_user' OR is_super_user = true)
  );
$$;

CREATE OR REPLACE FUNCTION public.crm_current_coach_id()
RETURNS uuid
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT id FROM public.profiles
  WHERE auth_user_id = auth.uid()
    AND role IN ('coach', 'super_user')
    AND status = 'active'
  LIMIT 1;
$$;

-- Supabase grants EXECUTE on new functions to anon by default; revoke it
-- explicitly so only signed-in users can call anything CRM-related.
REVOKE ALL ON FUNCTION public.crm_is_coach()          FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.crm_is_super()          FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.crm_current_coach_id()  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.crm_is_coach()         TO authenticated;
GRANT EXECUTE ON FUNCTION public.crm_is_super()         TO authenticated;
GRANT EXECUTE ON FUNCTION public.crm_current_coach_id() TO authenticated;


-- =============================================
-- 2. TABLES
-- =============================================

CREATE TABLE IF NOT EXISTS public.crm_contacts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name       TEXT NOT NULL DEFAULT '',
  email           TEXT,
  phone           TEXT,
  relationship    TEXT,
  notes           TEXT,
  do_not_contact  BOOLEAN NOT NULL DEFAULT FALSE,
  created_by      UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT crm_contacts_identifiable
    CHECK (btrim(full_name) <> '' OR email IS NOT NULL OR phone IS NOT NULL)
);

-- One contact per email address (case-insensitive); siblings share a contact.
CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_contacts_email
  ON public.crm_contacts (lower(email)) WHERE email IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.crm_leads (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id          UUID REFERENCES public.crm_contacts(id) ON DELETE SET NULL,
  first_name          TEXT NOT NULL CHECK (btrim(first_name) <> ''),
  last_name           TEXT,
  date_of_birth       DATE,
  gender              TEXT CHECK (gender IS NULL OR gender IN ('Male', 'Female', 'Other')),
  diver_email         TEXT,
  diver_phone         TEXT,
  stage               TEXT NOT NULL DEFAULT 'lead'
                        CHECK (stage IN ('lead', 'registered', 'trial_completed',
                                         'member', 'graduated', 'dropped', 'no_contact')),
  source              TEXT,
  campaign            TEXT,
  trial_date          DATE,
  follow_up_date      DATE,
  last_contacted_at   TIMESTAMPTZ,
  assigned_coach_id   UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  notes               TEXT,
  converted_diver_id  UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  converted_at        TIMESTAMPTZ,
  created_by          UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_leads_converted_diver
  ON public.crm_leads (converted_diver_id) WHERE converted_diver_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_crm_leads_stage      ON public.crm_leads (stage);
CREATE INDEX IF NOT EXISTS idx_crm_leads_contact    ON public.crm_leads (contact_id);
CREATE INDEX IF NOT EXISTS idx_crm_leads_followup   ON public.crm_leads (follow_up_date)
  WHERE follow_up_date IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_crm_leads_source     ON public.crm_leads (source, campaign);

CREATE TABLE IF NOT EXISTS public.crm_activities (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id      UUID NOT NULL REFERENCES public.crm_leads(id) ON DELETE CASCADE,
  kind         TEXT NOT NULL DEFAULT 'note'
                 CHECK (kind IN ('note', 'call', 'email', 'text', 'in_person', 'trial', 'other')),
  body         TEXT NOT NULL DEFAULT '',
  occurred_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by   UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_crm_activities_lead ON public.crm_activities (lead_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS public.crm_stage_history (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id     UUID NOT NULL REFERENCES public.crm_leads(id) ON DELETE CASCADE,
  from_stage  TEXT,
  to_stage    TEXT NOT NULL,
  changed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  changed_by  UUID REFERENCES public.profiles(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_crm_stage_history_lead ON public.crm_stage_history (lead_id, changed_at);


-- =============================================
-- 3. TRIGGERS
-- =============================================

CREATE OR REPLACE FUNCTION public.crm_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS crm_contacts_set_updated_at ON public.crm_contacts;
CREATE TRIGGER crm_contacts_set_updated_at
  BEFORE UPDATE ON public.crm_contacts
  FOR EACH ROW EXECUTE FUNCTION public.crm_set_updated_at();

DROP TRIGGER IF EXISTS crm_leads_set_updated_at ON public.crm_leads;
CREATE TRIGGER crm_leads_set_updated_at
  BEFORE UPDATE ON public.crm_leads
  FOR EACH ROW EXECUTE FUNCTION public.crm_set_updated_at();

-- Member/Graduated mean "exists in DivePractice", so they are only valid
-- once a diver profile is linked. Fires on stage writes only, so a diver
-- profile being deleted later (FK sets converted_diver_id to NULL) is not
-- blocked by it.
CREATE OR REPLACE FUNCTION public.crm_leads_stage_guard()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.stage IN ('member', 'graduated') AND NEW.converted_diver_id IS NULL THEN
    RAISE EXCEPTION 'A lead can only become a Member or Graduated by being converted to a diver';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS crm_leads_stage_guard ON public.crm_leads;
CREATE TRIGGER crm_leads_stage_guard
  BEFORE INSERT OR UPDATE OF stage ON public.crm_leads
  FOR EACH ROW EXECUTE FUNCTION public.crm_leads_stage_guard();

CREATE OR REPLACE FUNCTION public.crm_leads_log_stage()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.crm_stage_history (lead_id, from_stage, to_stage, changed_by)
    VALUES (NEW.id, NULL, NEW.stage, public.crm_current_coach_id());
  ELSIF NEW.stage IS DISTINCT FROM OLD.stage THEN
    INSERT INTO public.crm_stage_history (lead_id, from_stage, to_stage, changed_by)
    VALUES (NEW.id, OLD.stage, NEW.stage, public.crm_current_coach_id());
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS crm_leads_log_stage ON public.crm_leads;
CREATE TRIGGER crm_leads_log_stage
  AFTER INSERT OR UPDATE OF stage ON public.crm_leads
  FOR EACH ROW EXECUTE FUNCTION public.crm_leads_log_stage();

-- Logging a call/email/text/in-person contact stamps the lead's
-- last_contacted_at (never moves it backwards).
CREATE OR REPLACE FUNCTION public.crm_activities_touch_lead()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.kind IN ('call', 'email', 'text', 'in_person') THEN
    UPDATE public.crm_leads
    SET last_contacted_at = GREATEST(COALESCE(last_contacted_at, NEW.occurred_at), NEW.occurred_at)
    WHERE id = NEW.lead_id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS crm_activities_touch_lead ON public.crm_activities;
CREATE TRIGGER crm_activities_touch_lead
  AFTER INSERT ON public.crm_activities
  FOR EACH ROW EXECUTE FUNCTION public.crm_activities_touch_lead();


-- =============================================
-- 4. ROW LEVEL SECURITY
-- =============================================

ALTER TABLE public.crm_contacts      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_leads         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_activities    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_stage_history ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.crm_contacts, public.crm_leads, public.crm_activities,
              public.crm_stage_history FROM anon;

DROP POLICY IF EXISTS "crm_contacts: coach select" ON public.crm_contacts;
DROP POLICY IF EXISTS "crm_contacts: coach insert" ON public.crm_contacts;
DROP POLICY IF EXISTS "crm_contacts: coach update" ON public.crm_contacts;
DROP POLICY IF EXISTS "crm_contacts: super delete" ON public.crm_contacts;

CREATE POLICY "crm_contacts: coach select" ON public.crm_contacts
  FOR SELECT TO authenticated USING (public.crm_is_coach());
CREATE POLICY "crm_contacts: coach insert" ON public.crm_contacts
  FOR INSERT TO authenticated WITH CHECK (public.crm_is_coach());
CREATE POLICY "crm_contacts: coach update" ON public.crm_contacts
  FOR UPDATE TO authenticated USING (public.crm_is_coach()) WITH CHECK (public.crm_is_coach());
CREATE POLICY "crm_contacts: super delete" ON public.crm_contacts
  FOR DELETE TO authenticated USING (public.crm_is_super());

DROP POLICY IF EXISTS "crm_leads: coach select" ON public.crm_leads;
DROP POLICY IF EXISTS "crm_leads: coach insert" ON public.crm_leads;
DROP POLICY IF EXISTS "crm_leads: coach update" ON public.crm_leads;
DROP POLICY IF EXISTS "crm_leads: super delete" ON public.crm_leads;

CREATE POLICY "crm_leads: coach select" ON public.crm_leads
  FOR SELECT TO authenticated USING (public.crm_is_coach());
CREATE POLICY "crm_leads: coach insert" ON public.crm_leads
  FOR INSERT TO authenticated WITH CHECK (public.crm_is_coach());
CREATE POLICY "crm_leads: coach update" ON public.crm_leads
  FOR UPDATE TO authenticated USING (public.crm_is_coach()) WITH CHECK (public.crm_is_coach());
CREATE POLICY "crm_leads: super delete" ON public.crm_leads
  FOR DELETE TO authenticated USING (public.crm_is_super());

DROP POLICY IF EXISTS "crm_activities: coach select" ON public.crm_activities;
DROP POLICY IF EXISTS "crm_activities: coach insert" ON public.crm_activities;
DROP POLICY IF EXISTS "crm_activities: author or super delete" ON public.crm_activities;

CREATE POLICY "crm_activities: coach select" ON public.crm_activities
  FOR SELECT TO authenticated USING (public.crm_is_coach());
CREATE POLICY "crm_activities: coach insert" ON public.crm_activities
  FOR INSERT TO authenticated WITH CHECK (public.crm_is_coach());
CREATE POLICY "crm_activities: author or super delete" ON public.crm_activities
  FOR DELETE TO authenticated
  USING (public.crm_is_super() OR created_by = public.crm_current_coach_id());

-- History is written only by the stage trigger (SECURITY DEFINER); coaches read it.
DROP POLICY IF EXISTS "crm_stage_history: coach select" ON public.crm_stage_history;
CREATE POLICY "crm_stage_history: coach select" ON public.crm_stage_history
  FOR SELECT TO authenticated USING (public.crm_is_coach());


-- =============================================
-- 5. RPC: crm_import_leads
-- Atomically upserts parent contacts and inserts leads. Used by both the
-- CSV import and the single "Add lead" form. Each row is a JSON object:
--   first_name (required), last_name, parent_name, parent_email,
--   parent_phone, diver_email, diver_phone, date_of_birth (YYYY-MM-DD),
--   gender, source, campaign, notes, stage
-- Contacts are matched by email (case-insensitive), else by name+phone.
-- A lead is skipped as a duplicate when the same contact already has a
-- lead with the same first+last name. 'member' / 'graduated' are not
-- accepted as an imported stage (those come from conversion).
-- Returns: { inserted, skipped, contacts_created, lead_ids, skipped_rows }
-- =============================================

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
  v_pemail    TEXT;
  v_pphone    TEXT;
  v_dob       DATE;
  v_gender    TEXT;
  v_stage     TEXT;
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
    v_first  := NULLIF(btrim(COALESCE(v_item.item->>'first_name', '')), '');
    v_last   := NULLIF(btrim(COALESCE(v_item.item->>'last_name', '')), '');
    v_pname  := NULLIF(btrim(COALESCE(v_item.item->>'parent_name', '')), '');
    v_pemail := lower(NULLIF(btrim(COALESCE(v_item.item->>'parent_email', '')), ''));
    v_pphone := NULLIF(btrim(COALESCE(v_item.item->>'parent_phone', '')), '');

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
        INSERT INTO public.crm_contacts (full_name, email, phone, created_by)
        VALUES (COALESCE(v_pname, ''), v_pemail, v_pphone, v_coach)
        RETURNING id INTO v_contact;
        v_contacts := v_contacts + 1;
      ELSE
        UPDATE public.crm_contacts
        SET full_name = CASE WHEN btrim(full_name) = '' THEN COALESCE(v_pname, '') ELSE full_name END,
            phone     = COALESCE(phone, v_pphone)
        WHERE id = v_contact;
      END IF;
    ELSIF v_pname IS NOT NULL OR v_pphone IS NOT NULL THEN
      SELECT id INTO v_contact
      FROM public.crm_contacts
      WHERE email IS NULL
        AND lower(btrim(full_name)) = lower(COALESCE(v_pname, ''))
        AND COALESCE(phone, '') = COALESCE(v_pphone, '')
      LIMIT 1;
      IF v_contact IS NULL THEN
        INSERT INTO public.crm_contacts (full_name, phone, created_by)
        VALUES (COALESCE(v_pname, ''), v_pphone, v_coach)
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
      diver_email, diver_phone, stage, source, campaign, notes, created_by
    )
    VALUES (
      v_contact, v_first, v_last, v_dob, v_gender,
      NULLIF(btrim(COALESCE(v_item.item->>'diver_email', '')), ''),
      NULLIF(btrim(COALESCE(v_item.item->>'diver_phone', '')), ''),
      v_stage,
      COALESCE(NULLIF(btrim(COALESCE(v_item.item->>'source', '')), ''), NULLIF(btrim(COALESCE(p_default_source, '')), '')),
      COALESCE(NULLIF(btrim(COALESCE(v_item.item->>'campaign', '')), ''), NULLIF(btrim(COALESCE(p_default_campaign, '')), '')),
      NULLIF(btrim(COALESCE(v_item.item->>'notes', '')), ''),
      v_coach
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


-- =============================================
-- 6. RPC: crm_convert_lead_to_diver  (the DivePractice handoff)
-- Creates the diver exactly as the roster page's "Add Diver" does
-- (create_unclaimed_diver, v39): an 'unclaimed' diver profile plus a roster
-- row, so the existing invite / claim / parent-link flows work unchanged.
-- Parent name/email/phone come from the linked CRM contact. CRM notes are
-- deliberately NOT copied: profiles.notes is readable by the diver and
-- linked parents, whereas CRM notes are internal.
-- The lead moves to 'member' and keeps a link to the new diver.
-- =============================================

CREATE OR REPLACE FUNCTION public.crm_convert_lead_to_diver(
  p_lead_id          UUID,
  p_current_level    INTEGER DEFAULT 0,
  p_assigned_coach_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_coach_id    UUID := public.crm_current_coach_id();
  v_lead        public.crm_leads%ROWTYPE;
  v_contact     public.crm_contacts%ROWTYPE;
  v_roster_coach UUID;
  v_coach_name  TEXT;
  v_profile_id  UUID;
BEGIN
  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'Only active coaches can do this';
  END IF;

  IF p_current_level IS NOT NULL AND (p_current_level < 0 OR p_current_level > 12) THEN
    RAISE EXCEPTION 'Level must be between 0 and 12';
  END IF;

  SELECT * INTO v_lead FROM public.crm_leads WHERE id = p_lead_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lead not found';
  END IF;
  IF v_lead.converted_diver_id IS NOT NULL THEN
    RAISE EXCEPTION 'This lead has already been converted to a diver';
  END IF;

  IF v_lead.contact_id IS NOT NULL THEN
    SELECT * INTO v_contact FROM public.crm_contacts WHERE id = v_lead.contact_id;
  END IF;

  v_roster_coach := COALESCE(p_assigned_coach_id, v_lead.assigned_coach_id, v_coach_id);

  SELECT full_name INTO v_coach_name
  FROM public.profiles
  WHERE id = v_roster_coach
    AND role IN ('coach', 'super_user')
    AND status = 'active';
  IF v_coach_name IS NULL THEN
    RAISE EXCEPTION 'Selected coach is not valid';
  END IF;

  INSERT INTO public.profiles (
    first_name, last_name, email, role, status,
    date_of_birth, current_level, phone,
    parent_guardian_name, parent_email, parent_phone,
    created_by_coach_id, gender, assigned_coach_name, start_date
  )
  VALUES (
    v_lead.first_name,
    v_lead.last_name,
    v_lead.diver_email,
    'diver',
    'unclaimed',
    v_lead.date_of_birth,
    p_current_level,
    v_lead.diver_phone,
    NULLIF(btrim(COALESCE(v_contact.full_name, '')), ''),
    v_contact.email,
    v_contact.phone,
    v_coach_id,
    v_lead.gender,
    v_coach_name,
    CURRENT_DATE
  )
  RETURNING id INTO v_profile_id;

  INSERT INTO public.roster (coach_id, diver_id) VALUES (v_roster_coach, v_profile_id);

  UPDATE public.crm_leads
  SET converted_diver_id = v_profile_id,
      converted_at       = NOW(),
      assigned_coach_id  = v_roster_coach,
      stage              = 'member'
  WHERE id = p_lead_id;

  INSERT INTO public.crm_activities (lead_id, kind, body, created_by)
  VALUES (p_lead_id, 'other', 'Converted to a DivePractice diver profile', v_coach_id);

  RETURN v_profile_id;
END;
$$;

REVOKE ALL ON FUNCTION public.crm_import_leads(JSONB, TEXT, TEXT)           FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.crm_convert_lead_to_diver(UUID, INTEGER, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.crm_import_leads(JSONB, TEXT, TEXT)           TO authenticated;
GRANT EXECUTE ON FUNCTION public.crm_convert_lead_to_diver(UUID, INTEGER, UUID) TO authenticated;
