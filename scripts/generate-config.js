// Runs at Netlify build time to write js/config.js from environment variables.
// Not committed to git — generated fresh on every deploy.
const fs = require('fs');
const path = require('path');

const required = [
  'SUPABASE_URL',
  'SUPABASE_ANON_KEY',
];

const missing = required.filter(k => !process.env[k]);
if (missing.length) {
  console.error(`Missing required environment variables: ${missing.join(', ')}`);
  console.error('Set them in Netlify -> Site configuration -> Environment variables.');
  process.exit(1);
}

const config = `// Auto-generated at build time from Netlify environment variables. Do not edit.
const CONFIG = {
  SUPABASE_URL:      '${process.env.SUPABASE_URL}',
  SUPABASE_ANON_KEY: '${process.env.SUPABASE_ANON_KEY}',
  APP_NAME:          'Dive Drills',
  APP_VERSION:       '1.0.0',
};

// TEMPORARY: confirm credentials were read correctly at runtime (first 10
// chars only, never the full value). Remove once verified.
console.log('[DiveDrills] SUPABASE_URL starts with:', CONFIG.SUPABASE_URL.slice(0, 10));
console.log('[DiveDrills] SUPABASE_ANON_KEY starts with:', CONFIG.SUPABASE_ANON_KEY.slice(0, 10));

function initSupabase() {
  if (typeof supabase === 'undefined') {
    console.error('[DiveDrills] Supabase SDK not found. Check the CDN <script> tag.');
    return null;
  }
  window.supabaseClient = supabase.createClient(
    CONFIG.SUPABASE_URL,
    CONFIG.SUPABASE_ANON_KEY,
    {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    }
  );
  return window.supabaseClient;
}
`;

fs.writeFileSync(path.join(__dirname, '..', 'js', 'config.js'), config);
console.log('js/config.js generated successfully.');
