# 🤿 Dive Drills

> Skills tracker for competitive divers — Level 0 through Level 12.

A mobile-first web app for coaching staff, divers, and parents.  
**Stack:** Vanilla HTML/CSS/JS · Supabase (auth + DB) · Airtable (skills library) · Netlify (hosting)

---

## Quick Start

### 1. Supabase — create your database

1. Go to [supabase.com](https://supabase.com) and create a new project.
2. Open **SQL Editor → New Query**.
3. Paste the entire contents of `supabase-setup.sql` and run it.
4. Copy your **Project URL** and **anon public key** from  
   *Settings → API*.

### 2. Airtable — verify your skills table

Your base ID is already set: `app3YAcLp5MeTNYoO`

Make sure your **Skills** table has these exact field names:
| Field | Type |
|---|---|
| `Skill Name` | Single line text |
| `# Skill Level` | Number (0–12) |
| `Skill Type` | Single select |
| `Skill Description` | Long text |
| `Skill Category` | Single select |
| `Video URL` | URL *(add this)* |
| `Coaching Notes` | Long text *(add this)* |

Generate a **Personal Access Token** at [airtable.com/create/tokens](https://airtable.com/create/tokens).  
Scopes needed: `data.records:read`, `schema.bases:read`

### 3. Add your credentials

Open `js/config.js` and replace the placeholders:

```js
SUPABASE_URL:      'https://your-project-id.supabase.co',
SUPABASE_ANON_KEY: 'your-supabase-anon-key-here',
AIRTABLE_API_KEY:  'your-airtable-personal-access-token-here',
```

### 4. Create your first user accounts

In **Supabase → Authentication → Users → Invite User**, create accounts for:
- The head coach (role: `coach`)
- Each diver (role: `diver`)
- Parents (role: `parent`)

The Supabase trigger in `supabase-setup.sql` auto-creates a `profiles` row on signup.  
To set the role, pass it as user metadata when inviting, or manually update the `profiles` table.

> **Quick manual setup:** After a user signs up, go to  
> *Supabase → Table Editor → profiles* and set their `role` field.

### 5. Deploy to Netlify

```bash
# Option A: Drag-and-drop the folder onto netlify.com/drop

# Option B: Connect your GitHub repo
# 1. git init && git add . && git commit -m "initial"
# 2. Push to GitHub
# 3. netlify.com → New site → Import from Git
# Build command: (leave blank)
# Publish directory: .
```

---

## File Structure

```
diving-skills-app/
├── index.html          ← Login page
├── dashboard.html      ← Home (role-aware)
├── skills.html         ← Skills library browser
├── profile.html        ← User profile
├── progress.html       ← Progress tracker (Levels 0–12)
├── roster.html         ← Coach: manage divers
├── css/
│   └── styles.css      ← Full design system
├── js/
│   ├── config.js       ← 🔑 Credentials go here
│   ├── auth.js         ← Login/logout/session/role
│   ├── supabase.js     ← All DB calls
│   ├── airtable.js     ← Airtable API calls
│   └── app.js          ← Nav, toasts, shared helpers
├── supabase-setup.sql  ← Run this once in Supabase
├── netlify.toml        ← Netlify config + headers
└── README.md
```

---

## User Roles

| Role | Can do |
|---|---|
| **Coach** | Full access. View all divers. Confirm skills. Edit skills in Airtable. |
| **Diver** | Own profile + progress only. Browse skills. Self-report completions. |
| **Parent** | Read-only. View linked diver's progress. Browse skills library. |

---

## Color Palette

| Token | Value | Usage |
|---|---|---|
| `--bg-primary` | `#0f0f0f` | Page background |
| `--bg-surface` | `#1a1a1a` | Cards, sidebar |
| `--bg-surface-2` | `#242424` | Inputs, nested surfaces |
| `--border` | `#2e2e2e` | All borders |
| `--text-primary` | `#f0f0f0` | Headings, body copy |
| `--text-secondary` | `#a0a0a0` | Labels, hints |
| `--accent` | `#00c9a7` | Buttons, highlights, confirmed |
| `--pending` | `#f5a623` | Self-reported, awaiting confirmation |

---

## Roadmap / Next Steps

- [ ] Add video embed player inside the skill modal
- [ ] Coach can add/edit coaching notes inline (write back to Airtable)
- [ ] Push notifications when a coach confirms a skill (Supabase Realtime)
- [ ] Parent account linking UI (currently set manually in Supabase)
- [ ] Bulk CSV import for initial skill completion data
- [ ] Offline support via Service Worker (for poolside use with spotty wifi)
- [ ] Avatar upload via Supabase Storage
