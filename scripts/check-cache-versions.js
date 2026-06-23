#!/usr/bin/env node
// Cache version consistency checker.
// Run from the project root: node scripts/check-cache-versions.js
// Exits with code 1 if any inconsistency is found.

const fs   = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');

const TRACKED = [
  { file: 'js/app.js',       pattern: /js\/app\.js\?v=(\d+)/g },
  { file: 'js/supabase.js',  pattern: /js\/supabase\.js\?v=(\d+)/g },
  { file: 'js/auth.js',      pattern: /js\/auth\.js\?v=(\d+)/g },
  { file: 'js/skills.js',    pattern: /js\/skills\.js\?v=(\d+)/g },
  { file: 'css/styles.css',  pattern: /css\/styles\.css\?v=(\d+)/g },
];

const htmlFiles = fs.readdirSync(ROOT)
  .filter(f => f.endsWith('.html'))
  .sort();

let hasError = false;

console.log('\nCache version check\n' + '─'.repeat(50));

for (const { file, pattern } of TRACKED) {
  const versions = {};   // version → [html files using it]
  const missing  = [];   // html files with no reference at all

  for (const html of htmlFiles) {
    const content = fs.readFileSync(path.join(ROOT, html), 'utf8');
    pattern.lastIndex = 0;
    const matches = [...content.matchAll(pattern)];

    if (matches.length === 0) {
      // Only flag as missing if the file is expected to load this asset.
      // (skills.js is only on skills.html — other pages legitimately omit it)
      const isExpected = file !== 'js/skills.js' ||
        content.includes('skills.js');
      if (isExpected && content.includes(file.split('?')[0].split('/').pop())) {
        missing.push(html);
      }
    } else {
      for (const m of matches) {
        const v = m[1];
        if (!versions[v]) versions[v] = [];
        versions[v].push(html);
      }
    }
  }

  const versionKeys = Object.keys(versions);
  const totalFiles  = versionKeys.reduce((sum, v) => sum + versions[v].length, 0);

  if (versionKeys.length === 0) {
    // Asset not referenced anywhere — skip
    continue;
  }

  if (versionKeys.length === 1) {
    console.log(`  ✓  ${file.padEnd(20)} v=${versionKeys[0]}  (${totalFiles} files)`);
  } else {
    hasError = true;
    console.log(`  ✗  ${file} — INCONSISTENT VERSIONS:`);
    for (const v of versionKeys.sort((a, b) => Number(a) - Number(b))) {
      console.log(`       v=${v} used in: ${versions[v].join(', ')}`);
    }
  }

  if (missing.length) {
    hasError = true;
    console.log(`  ✗  ${file} — MISSING version string in: ${missing.join(', ')}`);
  }
}

if (hasError) {
  console.log('\n✗ Fix the inconsistencies above before pushing.\n');
  process.exit(1);
} else {
  console.log('\n✓ All cache versions are consistent.\n');
}
