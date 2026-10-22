-- v75: Onboarding checklist columns on crm_leads
-- Tracks whether each new diver has been set up in the required tools/systems.

ALTER TABLE public.crm_leads
  ADD COLUMN IF NOT EXISTS onboard_quickbooks   boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS onboard_alora        boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS onboard_zoho         boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS onboard_groupme      boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS onboard_divedrills   boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS onboard_aau          boolean NOT NULL DEFAULT false;

-- After Oct 30 2026 Supabase requires explicit grants for new columns on existing tables.
GRANT UPDATE (onboard_quickbooks, onboard_alora, onboard_zoho, onboard_groupme, onboard_divedrills, onboard_aau)
  ON public.crm_leads TO authenticated, service_role;
