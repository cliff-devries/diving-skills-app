async function initSupabase() {
  if (typeof supabase === 'undefined') {
    console.error('[DivingSkills] Supabase SDK not found. Check the CDN <script> tag.');
    return null;
  }
  const res = await fetch('/.netlify/functions/get-config');
  if (!res.ok) {
    console.error('[DivingSkills] Failed to load config:', res.status);
    return null;
  }
  const { SUPABASE_URL, SUPABASE_ANON_KEY } = await res.json();
  window.supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: {
      persistSession:    true,
      autoRefreshToken:  true,
      detectSessionInUrl: true,
    },
  });
  return window.supabaseClient;
}
