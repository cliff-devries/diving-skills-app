-- ============================================================
-- Migration v58 — DiveCRM: Graduated no longer needs a DivePractice link
-- Run once in the Supabase SQL editor (paste this file's text, not a .patch).
-- Safe to re-run (CREATE OR REPLACE).
--
-- v53's stage guard required a linked diver (converted_diver_id) for BOTH
-- 'member' and 'graduated'. A graduated diver has left the program, so
-- moving a contact to Graduated is now a plain stage change on the CRM row:
-- it creates, links and changes nothing in DivePractice. 'member' still
-- requires the link (crm_convert_lead_to_diver or
-- crm_link_lead_to_existing_diver), so that rule is unchanged.
--
-- Only the function body is replaced; the trigger created in v53
-- (crm_leads_stage_guard, BEFORE INSERT OR UPDATE OF stage) keeps using it.
-- ============================================================

CREATE OR REPLACE FUNCTION public.crm_leads_stage_guard()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.stage = 'member' AND NEW.converted_diver_id IS NULL THEN
    RAISE EXCEPTION 'A lead can only become a Member by being converted to a diver';
  END IF;
  RETURN NEW;
END;
$$;
