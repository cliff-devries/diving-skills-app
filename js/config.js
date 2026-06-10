// =============================================
// DIVE DRILLS — Configuration
// Supabase anon key is a public key designed for client-side use.
// Data is protected by RLS policies, not by keeping this key secret.
// Airtable API key is NOT here — it lives server-side in the Netlify Function.
// =============================================

const CONFIG = {
  SUPABASE_URL:      'https://mvrphtawmornoiwcfiop.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im12cnBodGF3bW9ybm9pd2NmaW9wIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk0NjIwODgsImV4cCI6MjA5NTAzODA4OH0.j8N328CjGvi75IiIZxR9oR_isIC9UVnIug1G4G-9Qm4',
  APP_NAME:          'Dive Drills',
  APP_VERSION:       '1.0.0',
};

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
