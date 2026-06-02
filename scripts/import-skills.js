// =============================================
// Import skills from Airtable CSV into Supabase
//
// Usage:
//   node scripts/import-skills.js <path-to-csv>
//
// Example:
//   node scripts/import-skills.js skills-export.csv
//
// Requirements: npm install @supabase/supabase-js csv-parse
// =============================================

const fs          = require('fs');
const path        = require('path');
const { parse }   = require('csv-parse/sync');
const { createClient } = require('@supabase/supabase-js');

// ---- Load credentials from config.js via regex (avoids eval) ----
const configPath = path.join(__dirname, '..', 'js', 'config.js');
const configText = fs.readFileSync(configPath, 'utf8');

function extractConfig(key) {
  const match = configText.match(new RegExp(`${key}:\\s*'([^']+)'`));
  if (!match) { console.error(`Could not find ${key} in js/config.js`); process.exit(1); }
  return match[1];
}

const SUPABASE_URL      = extractConfig('SUPABASE_URL');
const SUPABASE_ANON_KEY = extractConfig('SUPABASE_ANON_KEY');

// ---- CSV file path from CLI arg ----
const csvArg = process.argv[2];
if (!csvArg) {
  console.error('Usage: node scripts/import-skills.js <path-to-csv>');
  process.exit(1);
}
const csvPath = path.resolve(process.cwd(), csvArg);
if (!fs.existsSync(csvPath)) {
  console.error(`File not found: ${csvPath}`);
  process.exit(1);
}

// ---- Column mapping: CSV header → Supabase column ----
const COLUMN_MAP = {
  'Skill Name':        'skill_name',
  'Skill Level':       'skill_level',
  '# Skill Level':     'skill_level',   // Airtable sometimes exports with #
  'Skill Type':        'skill_type',
  'Skill Description': 'skill_description',
  'Skill Category':    'skill_category',
  'Belt Required':     'requires_harness',
  'Video URL':         'video_url',
  'Coaching Notes':    'coaching_notes',
};

// ---- Convert a CSV row to a Supabase insert row ----
function transformRow(csvRow, rowIndex) {
  const row = {};

  for (const [csvCol, dbCol] of Object.entries(COLUMN_MAP)) {
    if (!(csvCol in csvRow)) continue;

    const raw = (csvRow[csvCol] ?? '').trim();

    if (dbCol === 'skill_level') {
      const n = parseInt(raw, 10);
      if (isNaN(n) || n < 0 || n > 12) {
        throw new Error(`Row ${rowIndex}: skill_level "${raw}" is not an integer 0–12`);
      }
      row[dbCol] = n;

    } else if (dbCol === 'requires_harness') {
      // Treat "yes", "true", "1", "x", "checked" as true; everything else false
      row[dbCol] = /^(yes|true|1|x|checked)$/i.test(raw);

    } else if (dbCol === 'video_url') {
      row[dbCol] = raw || null;  // store null instead of empty string

    } else {
      row[dbCol] = raw;
    }
  }

  // skill_name and skill_level are required
  if (!row.skill_name) throw new Error(`Row ${rowIndex}: skill_name is empty`);
  if (row.skill_level === undefined) throw new Error(`Row ${rowIndex}: skill_level is missing`);

  return row;
}

async function main() {
  // ---- Parse CSV ----
  const raw = fs.readFileSync(csvPath, 'utf8');
  const records = parse(raw, {
    columns:          true,   // use first row as headers
    skip_empty_lines: true,
    trim:             true,
    bom:              true,   // handle Excel UTF-8 BOM
  });

  console.log(`Parsed ${records.length} rows from ${path.basename(csvPath)}`);

  // ---- Transform rows ----
  const rows = [];
  for (let i = 0; i < records.length; i++) {
    try {
      rows.push(transformRow(records[i], i + 2)); // +2 = 1-based + header row
    } catch (err) {
      console.error(`  ✗ ${err.message} — skipping`);
    }
  }

  if (rows.length === 0) {
    console.error('No valid rows to import. Aborting.');
    process.exit(1);
  }

  console.log(`Importing ${rows.length} valid rows…`);

  // ---- Insert into Supabase in batches of 100 ----
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const BATCH = 100;
  let inserted = 0;

  for (let offset = 0; offset < rows.length; offset += BATCH) {
    const batch = rows.slice(offset, offset + BATCH);
    const { error } = await supabase
      .from('skills')
      .insert(batch);

    if (error) {
      console.error(`Batch ${Math.floor(offset / BATCH) + 1} failed: ${error.message}`);
      process.exit(1);
    }
    inserted += batch.length;
    console.log(`  ✓ ${inserted}/${rows.length} rows inserted`);
  }

  console.log(`\nDone. ${inserted} skills imported successfully.`);
}

main().catch(err => {
  console.error('Unexpected error:', err.message);
  process.exit(1);
});
