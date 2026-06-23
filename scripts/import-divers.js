// =============================================
// Import divers from divers.csv into Supabase
//
// Usage:
//   SUPABASE_SERVICE_ROLE_KEY=... node scripts/import-divers.js [path-to-csv]
//
// Defaults to divers.csv in the project root.
//
// Requirements: npm install @supabase/supabase-js csv-parse
// =============================================

const fs    = require('fs');
const path  = require('path');
const { parse } = require('csv-parse/sync');
const { createClient } = require('@supabase/supabase-js');

const COACH_ID = '7c9b201b-d85a-48fa-ab64-5f414b2b27b8';

// ---- Load credentials from config.js via regex (avoids eval) ----
const configPath = path.join(__dirname, '..', 'js', 'config.js');
const configText = fs.readFileSync(configPath, 'utf8');

function extractConfig(key) {
  const match = configText.match(new RegExp(`${key}:\\s*'([^']+)'`));
  if (!match) { console.error(`Could not find ${key} in js/config.js`); process.exit(1); }
  return match[1];
}

const SUPABASE_URL = extractConfig('SUPABASE_URL');

// Service role key bypasses RLS — required to create profiles owned by another coach.
// Pass it via environment variable: SUPABASE_SERVICE_ROLE_KEY=... node scripts/import-divers.js
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!SERVICE_ROLE_KEY) {
  console.error('SUPABASE_SERVICE_ROLE_KEY environment variable is required.');
  console.error('Usage: SUPABASE_SERVICE_ROLE_KEY=... node scripts/import-divers.js [path-to-csv]');
  process.exit(1);
}

// ---- CSV file path (defaults to divers.csv in project root) ----
const csvArg  = process.argv[2] || 'divers.csv';
const csvPath = path.resolve(__dirname, '..', csvArg);
if (!fs.existsSync(csvPath)) {
  console.error(`File not found: ${csvPath}`);
  process.exit(1);
}

// ---- Convert a CSV row (all fields already trimmed) to a profiles insert row ----
function transformRow(row) {
  return {
    first_name:           row.first_name,
    last_name:            row.last_name || null,
    full_name:            [row.first_name, row.last_name].filter(Boolean).join(' '),
    role:                 'diver',
    status:               'unclaimed',
    current_level:        row.current_level !== '' ? parseInt(row.current_level, 10) : null,
    date_of_birth:        row.date_of_birth || null,
    phone:                row.phone || null,
    parent_guardian_name: row.parent_guardian_name || null,
    email:                row.email || null,
    gender:               row.gender || null,
    created_by_coach_id:  COACH_ID,
  };
}

function nameKey(firstName, lastName) {
  return `${(firstName || '').toLowerCase()}|${(lastName || '').toLowerCase()}`;
}

async function main() {
  // ---- Parse CSV ----
  const raw = fs.readFileSync(csvPath, 'utf8');
  const records = parse(raw, {
    columns:          true,   // use first row as headers
    skip_empty_lines: true,
    trim:             true,   // trim whitespace from every field
    bom:              true,   // handle Excel UTF-8 BOM
  });

  console.log(`Parsed ${records.length} rows from ${path.basename(csvPath)}`);

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  // ---- Load existing profiles to skip duplicates by first/last name ----
  const { data: existingProfiles, error: fetchError } = await supabase
    .from('profiles')
    .select('first_name, last_name');

  if (fetchError) {
    console.error(`Failed to load existing profiles: ${fetchError.message}`);
    process.exit(1);
  }

  const existingKeys = new Set(
    existingProfiles.map(p => nameKey(p.first_name, p.last_name))
  );

  let imported = 0;
  let skipped  = 0;

  for (const record of records) {
    const firstName = record.first_name;
    const lastName  = record.last_name;
    const key       = nameKey(firstName, lastName);

    if (existingKeys.has(key)) {
      console.log(`  - Skipped ${firstName} ${lastName} (already exists)`);
      skipped++;
      continue;
    }

    const profileRow = transformRow(record);

    const { data: profile, error: profileError } = await supabase
      .from('profiles')
      .insert(profileRow)
      .select('id')
      .single();

    if (profileError) {
      console.error(`  ✗ Failed to import ${firstName} ${lastName}: ${profileError.message}`);
      skipped++;
      continue;
    }

    const { error: rosterError } = await supabase
      .from('roster')
      .insert({ coach_id: COACH_ID, diver_id: profile.id });

    if (rosterError) {
      console.error(`  ✗ Failed to add ${firstName} ${lastName} to roster: ${rosterError.message}`);
      skipped++;
      continue;
    }

    console.log(`  ✓ Imported ${firstName} ${lastName}`);
    existingKeys.add(key);
    imported++;
  }

  console.log(`\nDone. ${imported} divers imported, ${skipped} skipped.`);
}

main().catch(err => {
  console.error('Unexpected error:', err.message);
  process.exit(1);
});
