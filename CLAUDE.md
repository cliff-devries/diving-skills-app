# Dive Drills — Claude Code Standing Instructions

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
- index.html (DiveCentral hub — self-contained, loads no project JS/CSS; nothing to bump)
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
| js/app.js | v=11 |
| js/supabase.js | v=37 |
| js/auth.js | v=3 |
| js/skills.js | v=4 |
| js/reports.js | v=11 |
| css/styles.css | v=10 |

---

## PROJECT STACK

Pure HTML/CSS/JS — no bundler, no build step. Supabase (auth + DB). Netlify (deploy from root).

**3 roles:** coach (full access), diver (own profile), parent (read-only linked diver)

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
- `member` / `graduated` are only reachable through the `crm_convert_lead_to_diver` RPC (a trigger enforces it). It creates
  the diver exactly like `create_unclaimed_diver` (unclaimed profile + roster row) and copies parent name/email/phone from
  the CRM contact. CRM notes are deliberately NOT copied: `profiles.notes` is readable by the diver and linked parents.
- After conversion the CRM row keeps a link (`converted_diver_id`) but parent/name edits do not sync — DivePractice owns the diver.
- Access is active coaches/super users only (`crm_is_coach()`); anon has no table or RPC access; hard delete is super-user only.
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
