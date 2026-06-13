console.log('Script starting...');

// =============================================
// Update skill_order on public.skills from skill_order.csv
//
// Usage:
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

async function main() {
  const { parse } = require('csv-parse/sync');
  const { createClient } = require('@supabase/supabase-js');

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
  // Pass it via environment variable: SUPABASE_SERVICE_ROLE_KEY=... node scripts/import-skill-order.js
  const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!SERVICE_ROLE_KEY) {
    throw new Error(
      'SUPABASE_SERVICE_ROLE_KEY environment variable is required.\n' +
      'Usage: SUPABASE_SERVICE_ROLE_KEY=... node scripts/import-skill-order.js [path-to-csv]'
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
