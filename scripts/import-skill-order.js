console.log('Script starting...');

// =============================================
// Update skill_order on public.skills from skill_order.csv
//
// Usage:
//   node scripts/import-skill-order.js [path-to-csv]
//
// Reads SUPABASE_SERVICE_ROLE_KEY from .env.local in the project root
// (one KEY=value per line — see .env.local for the expected format).
// You can also pass it via environment variable instead:
//   SUPABASE_SERVICE_ROLE_KEY=... node scripts/import-skill-order.js [path-to-csv]
//
// Defaults to skill_order.csv (underscore) in the project root.
//
// The CSV has three columns: Skill, Skill Level, Skill Number.
// Each row is matched to a skill by skill_name + skill_level (some
// skill names repeat across levels), and skill_order is set to the
// CSV's Skill Number.
//
// Requirements: npm install @supabase/supabase-js csv-parse
// =============================================

const fs   = require('fs');
const path = require('path');

// Match key: skill_name + skill_level, since some skill names repeat across levels.
function skillKey(name, level) {
  return `${name.trim().toLowerCase()}|${level}`;
}

// ---- Load KEY=value pairs from .env.local into process.env (without overwriting
// any vars already set in the environment) ----
function loadEnvLocal() {
  const envPath = path.join(__dirname, '..', '.env.local');
  if (!fs.existsSync(envPath)) return;

  for (const line of fs.readFileSync(envPath, 'utf8').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;

    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;

    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }

    if (!(key in process.env)) process.env[key] = value;
  }
}

async function main() {
  const { parse } = require('csv-parse/sync');
  const { createClient } = require('@supabase/supabase-js');

  loadEnvLocal();

  // ---- Load credentials from config.js via regex (avoids eval) ----
  const configPath = path.join(__dirname, '..', 'js', 'config.js');
  const configText = fs.readFileSync(configPath, 'utf8');

  function extractConfig(key) {
    const match = configText.match(new RegExp(`${key}:\\s*'([^']+)'`));
    if (!match) throw new Error(`Could not find ${key} in js/config.js`);
    return match[1];
  }

  const SUPABASE_URL = extractConfig('SUPABASE_URL');

  // Service role key bypasses RLS — required to update skills rows.
  // Set it in .env.local (SUPABASE_SERVICE_ROLE_KEY=...) or pass it via
  // environment variable: SUPABASE_SERVICE_ROLE_KEY=... node scripts/import-skill-order.js
  const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!SERVICE_ROLE_KEY) {
    throw new Error(
      'SUPABASE_SERVICE_ROLE_KEY is not set.\n' +
      'Add it to .env.local (SUPABASE_SERVICE_ROLE_KEY=...) or pass it via\n' +
      'environment variable: SUPABASE_SERVICE_ROLE_KEY=... node scripts/import-skill-order.js [path-to-csv]'
    );
  }

  // ---- CSV file path (defaults to skill_order.csv in project root) ----
  const csvArg  = process.argv[2] || 'skill_order.csv';
  const csvPath = path.resolve(__dirname, '..', csvArg);
  if (!fs.existsSync(csvPath)) {
    throw new Error(`File not found: ${csvPath}`);
  }

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

  // ---- Load all skills to match against ----
  const { data: skills, error: fetchError } = await supabase
    .from('skills')
    .select('id, skill_name, skill_level');

  if (fetchError) {
    throw new Error(`Failed to load skills: ${fetchError.message}`);
  }

  const skillByKey = new Map();
  for (const skill of skills) {
    skillByKey.set(skillKey(skill.skill_name, skill.skill_level), skill);
  }

  let updated = 0;
  const unmatched = [];

  for (const record of records) {
    const name  = record['Skill'] || '';
    const level = parseInt(record['Skill Level'], 10);
    const order = parseInt(record['Skill Number'], 10);

    if (!name || isNaN(level) || isNaN(order)) {
      unmatched.push(`${name || '(blank)'} — level "${record['Skill Level']}", number "${record['Skill Number']}" (invalid row)`);
      continue;
    }

    const skill = skillByKey.get(skillKey(name, level));
    if (!skill) {
      unmatched.push(`${name} (level ${level})`);
      continue;
    }

    const { error: updateError } = await supabase
      .from('skills')
      .update({ skill_order: order })
      .eq('id', skill.id);

    if (updateError) {
      console.error(`  ✗ Failed to update "${name}" (level ${level}): ${updateError.message}`);
      unmatched.push(`${name} (level ${level}) — update failed: ${updateError.message}`);
      continue;
    }

    console.log(`  ✓ ${name} (level ${level}) → skill_order ${order}`);
    updated++;
  }

  console.log(`\nDone. ${updated}/${records.length} skills matched and updated.`);

  if (unmatched.length) {
    console.log(`\n${unmatched.length} row(s) could not be matched to a skill:`);
    unmatched.forEach(u => console.log(`  - ${u}`));
  }
}

main().catch(err => {
  console.error('\nScript failed with an error:');
  console.error(err.message);
  if (err.stack) console.error(err.stack);
  process.exit(1);
});
