-- ============================================================
-- Migration v54 — DiveCRM services
-- Run once in the Supabase SQL editor. Safe to re-run.
--
-- crm_services: the programs Upstate Diving offers (Learn to Dive,
-- Private Lessons, …). A lead can be tagged with the service the family
-- is interested in via crm_leads.service_id.
--
-- ACCESS: same gate as the rest of the CRM (v53) — active coaches read,
-- add and edit; hard delete is super-user only (coaches mark a service
-- Inactive instead). anon gets nothing.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.crm_services (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL CHECK (btrim(name) <> ''),
  description TEXT,
  price_text  TEXT,
  status      TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  sort_order  INTEGER NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.crm_leads
  ADD COLUMN IF NOT EXISTS service_id UUID REFERENCES public.crm_services(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_crm_leads_service ON public.crm_leads (service_id);

ALTER TABLE public.crm_services ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.crm_services FROM anon;

DROP POLICY IF EXISTS "crm_services: coach select"  ON public.crm_services;
DROP POLICY IF EXISTS "crm_services: coach insert"  ON public.crm_services;
DROP POLICY IF EXISTS "crm_services: coach update"  ON public.crm_services;
DROP POLICY IF EXISTS "crm_services: super delete"  ON public.crm_services;

CREATE POLICY "crm_services: coach select" ON public.crm_services
  FOR SELECT TO authenticated USING (public.crm_is_coach());
CREATE POLICY "crm_services: coach insert" ON public.crm_services
  FOR INSERT TO authenticated WITH CHECK (public.crm_is_coach());
CREATE POLICY "crm_services: coach update" ON public.crm_services
  FOR UPDATE TO authenticated USING (public.crm_is_coach()) WITH CHECK (public.crm_is_coach());
CREATE POLICY "crm_services: super delete" ON public.crm_services
  FOR DELETE TO authenticated USING (public.crm_is_super());

-- Seed the default services once (only when the table is empty), here
-- rather than from the browser so it doesn't depend on who opens the
-- page first.
INSERT INTO public.crm_services (name, description, sort_order)
SELECT v.name, v.description, v.sort_order
FROM (VALUES
  ('Learn to Dive',        'Beginner introductory program.',                                   10),
  ('Private Lessons',      'One-on-one coaching sessions.',                                    20),
  ('Small Group Sessions', 'Small group training.',                                            30),
  ('Competition Team',     'Competitive diving program (Sparks, Fire, Blaze, Masters).',       40),
  ('RIT Collegiate',       'Rochester Institute of Technology diving team.',                   50)
) AS v(name, description, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM public.crm_services);
