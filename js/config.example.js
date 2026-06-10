// =============================================
// DIVE DRILLS — Configuration Template
// Copy this file to js/config.js and fill in your real values.
// js/config.js is excluded from git — never commit real credentials.
// =============================================

const CONFIG = {

  // ---- Supabase ------------------------------------------
  // Dashboard → Project → Settings → API
  // "Project URL" and "anon public" key
  SUPABASE_URL:      'https://your-project-id.supabase.co',
  SUPABASE_ANON_KEY: 'your-supabase-anon-key',

  // ---- Airtable ------------------------------------------
  // Base ID: visible in the API docs URL for your base
  // API Key: airtable.com → Account → Developer Hub → Personal Access Tokens
  // Scopes needed: data.records:read, schema.bases:read
  AIRTABLE_BASE_ID:      'appXXXXXXXXXXXXXX',
  AIRTABLE_API_KEY:      'patXXXXXXXXXXXXXX',
  AIRTABLE_SKILLS_TABLE: 'Skills',

  // ---- App Settings ----------------------------------------
  APP_NAME:    'Dive Drills',
  APP_VERSION: '1.0.0',
};

// =============================================
// Initialize the Supabase client.
// Called once per page BEFORE any auth/db calls.
// The resulting client is stored as window.supabaseClient.
// =============================================
function initSupabase() {
  if (typeof supabase === 'undefined') {
    console.error('[DiveDrills] Supabase SDK not found. Check the CDN <script> tag.');
    return null;
  }
  if (CONFIG.SUPABASE_URL.includes('your-project-id')) {
    console.warn('[DiveDrills] Supabase credentials are still placeholders. Update js/config.js.');
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
