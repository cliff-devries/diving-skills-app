-- ============================================================
-- Migration v57 — DiveCRM: link a lead to a diver already in DiveDrills
-- Run once in the Supabase SQL editor (paste this file's text, not a .patch).
-- Safe to re-run (CREATE OR REPLACE).
--
-- crm_link_lead_to_existing_diver(p_lead_id, p_diver_id)
--   For families whose diver is already a DivePractice profile. It moves the
--   lead to Member and records which existing profile it is, WITHOUT creating
--   a profile or a roster row and without copying anything onto the profile.
--   Linking (converted_diver_id) is what the stage guard from v53 requires
--   for Member, so the guard and crm_convert_lead_to_diver are unchanged.
--
-- Refuses when: caller is not an active coach, the lead is already linked,
-- the profile is not a diver, or that diver is already linked to another lead.
-- ============================================================

CREATE OR REPLACE FUNCTION public.crm_link_lead_to_existing_diver(
  p_lead_id  UUID,
  p_diver_id UUID
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_coach_id UUID := public.crm_current_coach_id();
  v_lead     public.crm_leads%ROWTYPE;
BEGIN
  IF v_coach_id IS NULL THEN
    RAISE EXCEPTION 'Only active coaches can do this';
  END IF;

  SELECT * INTO v_lead FROM public.crm_leads WHERE id = p_lead_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lead not found';
  END IF;
  IF v_lead.converted_diver_id IS NOT NULL THEN
    RAISE EXCEPTION 'This lead is already linked to a diver';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_diver_id AND role = 'diver'
  ) THEN
    RAISE EXCEPTION 'That diver profile was not found';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.crm_leads
    WHERE converted_diver_id = p_diver_id AND id <> p_lead_id
  ) THEN
    RAISE EXCEPTION 'That diver is already linked to another contact';
  END IF;

  UPDATE public.crm_leads
  SET converted_diver_id = p_diver_id,
      converted_at       = NOW(),
      stage              = 'member'
  WHERE id = p_lead_id;

  INSERT INTO public.crm_activities (lead_id, kind, body, created_by)
  VALUES (p_lead_id, 'other',
          'Linked to an existing DivePractice diver profile (no new profile created)',
          v_coach_id);

  RETURN p_diver_id;
END;
$$;

REVOKE ALL ON FUNCTION public.crm_link_lead_to_existing_diver(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.crm_link_lead_to_existing_diver(UUID, UUID) TO authenticated;
