# DiveDrills — Claude Code Standing Instructions

## CACHE BUSTING — MUST DO ON EVERY PUSH

This project uses manual cache-busting version strings on all JavaScript and CSS files.
Every time ANY JS or CSS file is modified, the version number for that file MUST be
bumped across ALL HTML files before pushing to GitHub.

### Files that need version bumping:
- `js/app.js?v=X` — bump when app.js changes
- `js/supabase.js?v=X` — bump when supabase.js changes
- `js/auth.js?v=X` — bump when auth.js changes
- `js/skills.js?v=X` — bump when skills.js changes
- `js/reports.js?v=X` — bump when reports.js changes (only on progress.html/stats.html)
- `css/styles.css?v=X` — bump when styles.css changes

### HTML files to update (ALL of them):
- index.html (public DiveCentral splash — no styles.css; bump its supabase.js/auth.js versions)
- hub.html (coach-only DiveCentral app hub — no styles.css; bump its supabase.js/auth.js versions)
- signup.html (public sign-up form — self-contained, loads no project JS/CSS; nothing to bump)
- info.html (short information-request form — self-contained, loads no project JS/CSS; nothing to bump)
- login.html (sign-in page — auth.js redirects here)
- dashboard.html
- skills.html
- progress.html
- roster.html
- profile.html
- testing.html
- stats.html
- welcome.html
- invite.html
- claim.html
- coach-signup.html
- leaderboard.html
- crm.html
- practice.html (no `css/styles.css` link — it's self-contained; only bump its JS versions)
- Any new HTML files added to the project

### Rule: Before every git push, run this check:

```bash
node scripts/check-cache-versions.js
```

Or manually:

```bash
grep -r "app\.js\|supabase\.js\|auth\.js\|skills\.js\|styles\.css" *.html | grep -v "?v="
```

If any file is missing a version string, add one before pushing.

### Version bump command pattern:

When bumping app.js from v5 to v6 across all HTML files:

```bash
sed -i '' 's/app\.js?v=5/app.js?v=6/g' *.html
```

**NEVER push a JS or CSS change without bumping the version string.**
**NEVER assume the browser will fetch fresh code without a version bump.**
This has caused repeated bugs throughout development.

### Current versions (update this table when bumping):

| File | Version |
|------|---------|
| js/app.js | v=13 |
| js/supabase.js | v=44 |
| js/auth.js | v=6 |
| js/skills.js | v=5 |
| js/reports.js | v=12 |
| css/styles.css | v=11 |

---

## PROJECT STACK

Pure HTML/CSS/JS — no bundler, no build step. Supabase (auth + DB). Netlify (deploy from root).

**3 roles:** coach (full access), diver (own profile), parent (read-only linked diver)

**Auth flow:** index.html is the public splash (signed-in users skip to their home). Signed-out users on a
protected page go to `login.html?redirect=<page>` and return there after sign-in (`Auth.safeRedirect` only
accepts same-site `*.html` pages). Without `?redirect=`, coaches/super users land on hub.html and
divers/parents on dashboard.html (`Auth.homeUrl`).

**DB tables:** profiles, roster, parent_diver, skill_completions, skill_test_attempts, level_completions, club_settings, skill_ratings, crm_contacts, crm_leads, crm_activities, crm_stage_history

**Script load order matters (no bundler):** config → supabase → auth → [skills] → app → [reports] → page inline script

---

## DATABASE NOTES

### profiles.status valid values

The `profiles_status_check` constraint allows these exact values:
- `'unclaimed'` — diver profile created by coach, not yet claimed
- `'pending'` — coach signup awaiting approval, or diver invite pending
- `'active'` — fully active account
- `'inactive'` — removed from roster (diver) or deactivated
- `'rejected'` — coach signup rejected

Any migration that sets `status` must use one of these values.

The constraint was widened to this full set in `supabase-migration-v34.sql` — the original
`supabase-migration-v3.sql` only allowed `('unclaimed', 'pending', 'active')`.

---

## CRM (crm.html, migration v53)

Upstate Diving's pre-membership pipeline lives in the same Supabase project as DivePractice.

- Stages (`crm_leads.stage`): `lead` (1) → `registered` (2) → `trial_completed` (3) → `member` (4) → `graduated` (5),
  plus `dropped` (D) and `no_contact` (N).
- `member` is only reachable through the `crm_convert_lead_to_diver` RPC (a trigger enforces it). `graduated` is a plain stage
  write on the CRM row with no DivePractice effect and needs no link (supabase-migration-v58.sql). The convert RPC creates
  the diver exactly like `create_unclaimed_diver` (unclaimed profile + roster row) and copies parent name/email/phone from
  the CRM contact. CRM notes are deliberately NOT copied: `profiles.notes` is readable by the diver and linked parents.
- After conversion the CRM row keeps a link (`converted_diver_id`) but parent/name edits do not sync — DivePractice owns the diver.
- Access is active coaches/super users only (`crm_is_coach()`); anon has no table or RPC access; hard delete is super-user only.
- crm.html is the standalone DiveCRM app (own header + hash tabs #dashboard (kanban)/#leads/#services/#activities/#reports,
  plus a full-page lead detail at #lead/<id>; blue `#2196F3` accent) — it does NOT call `App.renderNav()` and is not
  linked from the DiveDrills nav; it's reached from the DiveCentral hub (hub.html).
- Services live in `crm_services` (supabase-migration-v54.sql, which also adds `crm_leads.service_id` and seeds the
  defaults). crm.html degrades gracefully if v54 hasn't been run (Services tab shows a setup message).
- Sign-up form fields (supabase-migration-v55.sql): `crm_contacts` carries parent `last_name`, `street_address`, `city`,
  `zip_code`, `emergency_contact_name/phone`; `crm_leads` carries `signed_up_at`, `school_district`, `graduation_year`,
  `allergies_medical`, `prior_diving_experience`, `prior_gymnastics_experience`, `diving_location`, `aau_number`,
  `participates_in_competitions` (text 'yes'/'no'/'maybe' since v60, shown as "Interested in competition"); v56 adds `crm_leads.referred_by`. Diver birthdate is `date_of_birth` and "how did you find us" is `source`.
  `crm_leads.diver_email` / `diver_phone` were dropped in v55; the convert RPC no longer sets profile email/phone, and
  none of the new fields (address, allergies, etc.) are copied to `profiles`, same as notes. crm.html and
  `crmGetLeads` need v55 applied before the matching deploy.
- Divers already in DivePractice: `crm_link_lead_to_existing_diver` (supabase-migration-v57.sql) moves a lead to Member and links
  the existing profile without creating a profile or roster row (the "Convert to Diver - do not add to DiveDrills" button).
- Public sign-up (signup.html, also at /signup): posts to `netlify/functions/crm-signup.js`, which validates and calls
  `crm_public_signup` (supabase-migration-v59.sql). That RPC is executable by `service_role` ONLY, so anon still has no CRM
  table or RPC access. Needs the Netlify env var `SUPABASE_SERVICE_ROLE_KEY` (secret; never in js/config.js). It creates a
  `lead`-stage contact with `created_by` NULL, `signed_up_at` = now, `source` = the "how did you find us" answer (else
  'Web Form'), and a timeline note; a repeat submission only adds a note. Never return existing CRM data from it.
- Sign-up registers on the spot (supabase-migration-v69.sql + v70): the public form REQUIRES the AAU membership number AND the signed photo
  release/waiver (typed-name signature, text from `lib/release.js` fetched via GET on crm-signup; stored in `crm_consents` like the follow-up form),
  and `crm_public_signup` creates the contact at `registered` (stage history shows it). Registered = info form + AAU + signed release. Leads added by hand/imported stay in the Lead pool; a repeat
  submission by a diver still at Lead saves the AAU number and moves them to Registered. 
- The private follow-up form was retired (supabase-migration-v71.sql): the public sign-up form collects everything, and the follow-up page/function,
  `crm_followup_*` RPCs and `crm_leads.followup_token` are gone. Agreement wording and version live in `netlify/functions/lib/release.js` — never
  reword it; to change it, edit the text AND bump `VERSION` so past signatures keep the text that was actually shown. Signed releases are in
  `crm_consents` (exact text, version, typed name, time, IP, user-agent) and `crm_leads.release_signed_at/name`. A hand-added lead completes
  registration by submitting the sign-up form (matched by parent email + diver name); the `crm_leads_auto_register` trigger (v63) still moves a
  Lead to Registered once it has an AAU number AND a signed release. `{{followup_link}}` in an email template now just fills in the sign-up form URL.
- Information request form (info.html at /info, supabase-migration-v72.sql): parent first/last name, email and how they want to connect (follow-up email /
  follow-up call [asks for a phone] / join email list / talk with the bot [not built yet — see the project to-do]). Posts to `netlify/functions/crm-info.js` ->
  `crm_public_inquiry` (service_role only): creates the contact and a Lead with NO diver name (or just logs on an existing contact by email), stores
  `crm_leads.contact_preference`, no `signed_up_at` (so no automatic sign-up email), and emails the coach "Information request". When that parent later submits
  the full sign-up form, `crm_public_signup` fills in the nameless Lead instead of creating a duplicate.
- Coach notification emails (supabase-migration-v64.sql, `netlify/functions/lib/notify.js`): `crm-signup.js` emails
  cliff@upstatediving.com "New sign-up: <diver>" for a NEW lead only (a repeat submission sends nothing), (a repeat submission that moves a Lead to Registered emails "Registered: <diver>"). Sent through Brevo
  (`BREVO_API_KEY`, `BREVO_SENDER_EMAIL` must be a verified sender; optional `NOTIFY_EMAIL` overrides the recipient). A failed
  email never fails the sign-up. Emails carry only name/parent contact/location/source — never medical, allergy or release text.
- Emails tab (supabase-migration-v65.sql; `#emails` in crm.html): coaches write/edit templates (`crm_email_templates`: subject,
  plain-text body with `{{parent_first_name}} {{parent_name}} {{diver_first_name}} {{diver_name}} {{diving_location}}
  {{trial_date}} {{followup_link}}`) and choose a trigger: `manual` (Send email button on the contact page), `signup`
  (after the public form) or `stage_entered` (N minutes/hours/days after entering a stage, only if still in it), plus an
  optional Eastern-time send window (hour..9pm). Automatic emails only fire for events AFTER `enabled_at`, so switching one on
  never mails existing contacts, and `crm_email_log` has a unique index so a family gets each automatic template once.
  Skipped when the contact has no email or `do_not_contact`. Engine: `netlify/functions/lib/mailer.js` (Brevo; reply-to
  `NOTIFY_EMAIL`); `crm-email-scheduler.js` runs every 10 min (schedule in netlify.toml, production deploy only);
  `crm-signup.js` sends the "Sign-up confirmation" at once; `crm-send-email.js` handles preview/test/send for a coach, proving
  coach status by calling `crm_email_prepare` with the coach's own login (needs `SUPABASE_ANON_KEY`). `crm_email_due`,
  `crm_email_record` are service_role ONLY. Sends are logged on the contact's timeline (kind `email`) and
  in the Recent sends list. Every email carries a footer saying replying stops them.
  A `[[marker]]` in a template means "still to fill in" (a missing link or per-family blank): nothing containing one is ever
  sent (manual send is refused until edited, automatic can't be enabled, the scheduler skips it). The Send email box lets the
  coach edit subject/body before sending (`crm-send-email.js` then sends those exact words). `supabase-migration-v66.sql`
  seeded Upstate Diving's 13 existing emails (all manual, off); it never overwrites a template that already exists by name.
  `supabase-migration-v67.sql` finalizes them: real Instagram/Facebook/email-list links, the two "Information & Registration" emails send
  `{{followup_link}}`, RIT trial door/greeter times became `[[markers]]`, and the outdated 2024 Olympics email is removed. Each update only
  applies while the template text is still exactly what v66 loaded, so edits are never overwritten; v67 also works without v66.
- Add Lead (supabase-migration-v68.sql): only the parent/guardian FIRST name is required; the diver's first name is optional
  (`crm_leads.first_name` is nullable, never blank text). Parent first/last name sit side by side (`crm_contacts.full_name` is the
  parent's FIRST name, `last_name` the last). A nameless diver shows as "<parent> (parent)" via `leadName`, emails say "your diver", and
  Convert to Diver asks for the diver's first name first. Prior diving/gymnastics experience are selects: None / Some Training /
  Extensive Training (legacy free text still shows as an extra option when editing).
- Public page (signup.html) use the brand colors #020202 / #707070 and the Eras BQ title font
  (`assets/fonts/ErasBQ-Regular.woff2/.woff` if the font file is added; falls back to similar system fonts).
- All CRM DB calls are `SupabaseDB.crm*` methods in `js/supabase.js`. Pure helpers (CSV parse, header mapping, funnel math)
  sit between the `CRM-PURE-START` / `CRM-PURE-END` markers in crm.html and are unit-tested in Node.

---

## TEST REPORT PDFs (progress.html, stats.html)

- `js/reports.js` builds a light-theme PDF test report per diver/level, generated fresh from
  current DB state (no storage — a retest updates the report immediately).
- Uses jsPDF + html2canvas, loaded via CDN — add both `<script>` tags to any page that loads
  `js/reports.js`, before it.
- `netlify/functions/send-report-email.js` emails the PDF to a diver's linked **parent** (never
  the diver directly — youth-sports safety) via Brevo's REST API. Requires the Netlify env var
  `BREVO_API_KEY` (Site configuration → Environment variables); optionally `BREVO_SENDER_EMAIL`
  / `BREVO_SENDER_NAME` to override the default sender identity. The sender email must be a
  verified sender in the Brevo account or sends will fail.

---

## CODING RULES

- Run `node --check` on every JS file modified before pushing.
- No comments unless the WHY is non-obvious.
- No framework — keep it fast for poolside mobile on spotty wifi.
- SQL migrations go in `supabase-migration-vN.sql` — never modify old migration files.
