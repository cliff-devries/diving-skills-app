-- ============================================================
-- Migration v74 — convert raw URLs and [[LINK: ...]] markers
--                 to [Label](URL) syntax in email templates
--
-- Run once in the Supabase SQL editor.
-- Safe to re-run: every UPDATE checks the current body text.
--
-- Known URLs are replaced with [Label](URL) masked links.
-- Unknown links (GroupMe, survey, referral form) remain as
-- [[markers]] so the coach fills them in before sending.
-- ============================================================

-- Instagram bare URL → masked link
UPDATE public.crm_email_templates
  SET body = REPLACE(body,
    'https://www.instagram.com/upstatediving/',
    '[Upstate Diving on Instagram](https://www.instagram.com/upstatediving/)')
WHERE body LIKE '%https://www.instagram.com/upstatediving/%'
  AND body NOT LIKE '%[Upstate Diving on Instagram]%';

-- Facebook bare URL → masked link
UPDATE public.crm_email_templates
  SET body = REPLACE(body,
    'https://www.facebook.com/upstatenydiving',
    '[Upstate Diving on Facebook](https://www.facebook.com/upstatenydiving)')
WHERE body LIKE '%https://www.facebook.com/upstatenydiving%'
  AND body NOT LIKE '%[Upstate Diving on Facebook]%';

-- Zoho email signup bare URL → masked link
UPDATE public.crm_email_templates
  SET body = REPLACE(body,
    'https://zc.vg/0AP8k',
    '[Upstate Diving email sign-up form](https://zc.vg/0AP8k)')
WHERE body LIKE '%https://zc.vg/0AP8k%'
  AND body NOT LIKE '%[Upstate Diving email sign-up form]%';

-- [[LINK: AAU Diving]] → real masked link
UPDATE public.crm_email_templates
  SET body = REPLACE(body,
    '[[LINK: AAU Diving]]',
    '[AAU Diving](https://aaudivingnational.com/)')
WHERE body LIKE '%[[LINK: AAU Diving]]%';

-- [[LINK: AAU Sports Athlete Memberships]] → real masked link
UPDATE public.crm_email_templates
  SET body = REPLACE(body,
    '[[LINK: AAU Sports Athlete Memberships]]',
    '[AAU Sports Athlete Memberships](https://play.aausports.org/Account/Membership)')
WHERE body LIKE '%[[LINK: AAU Sports Athlete Memberships]]%';

-- [[LINK: RIT Campus Maps]] → real masked link
UPDATE public.crm_email_templates
  SET body = REPLACE(body,
    '[[LINK: RIT Campus Maps]]',
    '[RIT Campus Maps](https://www.rit.edu/maps)')
WHERE body LIKE '%[[LINK: RIT Campus Maps]]%';

-- [[LINK: Canandaigua Academy High School Map]] → real masked link
UPDATE public.crm_email_templates
  SET body = REPLACE(body,
    '[[LINK: Canandaigua Academy High School Map]]',
    '[Canandaigua Academy High School Map](https://maps.app.goo.gl/canandaigua-academy)')
WHERE body LIKE '%[[LINK: Canandaigua Academy High School Map]]%';

-- NOTE: The following stay as [[markers]] until the coach fills in the real URLs:
--   [[LINK: GroupMe]]
--   [[LINK: GroupMe Canandaigua]]
--   [[LINK: New Diver Survey]]
--   [[LINK: Referral Form]]
-- Edit those templates in the CRM Emails tab to replace them with [Label](URL).
