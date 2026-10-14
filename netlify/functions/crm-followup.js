// =============================================
// Netlify Function — private follow-up form -> DiveCRM.
// followup.html calls this with the long random token from the link a coach
// copied from the contact's page.
//   GET  ?t=<token>  -> { first_name, release_signed, release_version, release_text }
//   POST {t, aau_number, agree, signed_name, ...} -> saves the AAU number and/or
//        records the signed photo release & waiver.
// It calls crm_followup_get / crm_followup_submit (supabase-migration-v61.sql),
// which are executable by the service role only.
//
// Required Netlify environment variables:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY   (same as crm-signup.js)
// =============================================

const { VERSION, TEXT } = require('./lib/release.js');

const { notifyCoach } = require('./lib/notify.js');
const MIN_FILL_MS = 3000;
const MAX_BODY = 5000;
const TOKEN_RE = /^[0-9a-f]{64}$/;

const json = (statusCode, body) => ({
  statusCode,
  headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  body: JSON.stringify(body),
});

const str = (v, max) => String(v == null ? '' : v).trim().slice(0, max);

async function rpc(name, args) {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    console.error('crm-followup: SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is not set');
    return { ok: false, status: 500, data: null };
  }
  const res = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(args),
  });
  const text = await res.text().catch(() => '');
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = null; }
  if (!res.ok) console.error(`crm-followup: ${name} failed`, res.status, text);
  return { ok: res.ok, status: res.status, data };
}

const BAD_LINK = 'This link is not valid. Please ask Upstate Diving for a new one.';
const OOPS = 'Something went wrong. Please try again, or email or call us.';

exports.handler = async (event) => {
  if (event.httpMethod === 'GET') {
    const t = str(event.queryStringParameters && event.queryStringParameters.t, 80).toLowerCase();
    if (!TOKEN_RE.test(t)) return json(404, { success: false, error: BAD_LINK });
    try {
      const r = await rpc('crm_followup_get', { p_token: t });
      if (!r.ok) return json(500, { success: false, error: OOPS });
      if (!r.data || !r.data.found) return json(404, { success: false, error: BAD_LINK });
      return json(200, {
        success: true,
        first_name: r.data.first_name,
        release_signed: !!r.data.release_signed,
        has_aau: r.data.has_aau === true,
        release_version: VERSION,
        release_text: TEXT,
      });
    } catch (err) {
      console.error('crm-followup: get failed', err.message);
      return json(500, { success: false, error: OOPS });
    }
  }

  if (event.httpMethod !== 'POST') {
    return json(405, { success: false, error: 'Method not allowed.' });
  }
  if ((event.body || '').length > MAX_BODY) {
    return json(413, { success: false, error: 'That submission is too large.' });
  }

  let d;
  try { d = JSON.parse(event.body || '{}'); } catch { return json(400, { success: false, error: 'Invalid request.' }); }
  if (!d || typeof d !== 'object' || Array.isArray(d)) return json(400, { success: false, error: 'Invalid request.' });

  const t = str(d.t, 80).toLowerCase();
  if (!TOKEN_RE.test(t)) return json(404, { success: false, error: BAD_LINK });

  const filledMs = Date.now() - Number(d.loaded_at);
  if (str(d.website, 200) || !Number.isFinite(filledMs) || filledMs < MIN_FILL_MS) {
    return json(200, { success: true });
  }

  const aau = str(d.aau_number, 60);
  const agree = d.agree === true;
  const signedName = str(d.signed_name, 160);

  const NEED_AAU = 'Please enter the AAU membership number. Your diver cannot be on the pool deck without one.';
  if (!aau) {
    // A number already on file (typed by a coach or an earlier submission) counts.
    // Anything but an explicit yes means the number is required.
    try {
      const g = await rpc('crm_followup_get', { p_token: t });
      if (!g.ok) return json(500, { success: false, error: OOPS });
      if (!g.data || !g.data.found) return json(404, { success: false, error: BAD_LINK });
      if (g.data.has_aau !== true) return json(400, { success: false, error: NEED_AAU });
    } catch (err) {
      console.error('crm-followup: lookup failed', err.message);
      return json(500, { success: false, error: OOPS });
    }
  }
  if (agree && signedName.length < 2) {
    return json(400, { success: false, error: 'Please type your full name to sign.' });
  }
  if (!agree && signedName) {
    return json(400, { success: false, error: 'Please tick the box to confirm you agree, or clear the name field.' });
  }

  const ip = str((event.headers || {})['x-nf-client-connection-ip'] ||
    String((event.headers || {})['x-forwarded-for'] || '').split(',')[0], 64);
  const ua = str((event.headers || {})['user-agent'], 400);

  try {
    const r = await rpc('crm_followup_submit', {
      p_token: t,
      p_aau: aau,
      p_signed_name: agree ? signedName : '',
      p_version: VERSION,
      p_text: TEXT,
      p_ip: ip,
      p_ua: ua,
    });
    if (!r.ok) return json(500, { success: false, error: OOPS });
    if (!r.data || !r.data.found) return json(404, { success: false, error: BAD_LINK });
    if (r.data.ok === false) return json(400, { success: false, error: NEED_AAU });
    if (r.data.registered === true) {
      const diverName = r.data.diver_name || (r.data.parent_name ? `${r.data.parent_name}'s diver` : 'a diver');
      await notifyCoach({
        subject: `Registration complete: ${diverName} (Upstate Diving CRM)`,
        heading: 'Registration complete',
        leadId: r.data.lead_id,
        replyTo: r.data.parent_email,
        rows: [
          ['Diver', diverName],
          ['Parent / guardian', r.data.parent_name],
          ['Email', r.data.parent_email],
          ['Phone', r.data.parent_phone],
          ['Status', 'AAU number entered and photo release signed. Moved to Registered.'],
        ],
      });
    }
    return json(200, { success: true, signed: !!r.data.signed });
  } catch (err) {
    console.error('crm-followup: submit failed', err.message);
    return json(500, { success: false, error: OOPS });
  }
};
