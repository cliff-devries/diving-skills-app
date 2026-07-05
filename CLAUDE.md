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
- `css/styles.css?v=X` — bump when styles.css changes

### HTML files to update (ALL of them):
- index.html
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
| js/app.js | v=5 |
| js/supabase.js | v=13 |
| js/auth.js | v=2 |
| js/skills.js | v=4 |
| css/styles.css | v=5 |

---

## PROJECT STACK

Pure HTML/CSS/JS — no bundler, no build step. Supabase (auth + DB). Netlify (deploy from root).

**3 roles:** coach (full access), diver (own profile), parent (read-only linked diver)

**DB tables:** profiles, roster, parent_diver, skill_completions, skill_test_attempts, level_completions, club_settings

**Script load order matters (no bundler):** config → supabase → auth → [skills] → app → page inline script

---

## CODING RULES

- Run `node --check` on every JS file modified before pushing.
- No comments unless the WHY is non-obvious.
- No framework — keep it fast for poolside mobile on spotty wifi.
- SQL migrations go in `supabase-migration-vN.sql` — never modify old migration files.
