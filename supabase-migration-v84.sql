-- Migration v84: Add needs_follow_up flag to crm_leads
-- Adds a simple boolean flag coaches can toggle on a lead to mark it
-- as needing follow-up. Separate from follow_up_date (which is a
-- scheduled date); this is a manual "ping me" flag with no date required.

ALTER TABLE crm_leads
  ADD COLUMN IF NOT EXISTS needs_follow_up boolean NOT NULL DEFAULT false;

-- Index so the follow-up view query is fast.
CREATE INDEX IF NOT EXISTS crm_leads_needs_follow_up_idx
  ON crm_leads (needs_follow_up)
  WHERE needs_follow_up = true;
