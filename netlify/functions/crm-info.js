// =============================================
// Netlify Function — short "request information" form (info.html, /info) -> DiveCRM.
// Validates the submission and calls crm_public_inquiry
// (supabase-migration-v72.sql, executable by the service role only), then emails
// the coach. Same environment variables as crm-signup.js.
// =============================================

const { notifyCoach } = require('./lib/notify.js');

const MIN_FILL_MS = 3000;
const MAX_BODY = 5000;

const json = (statusCode, body) => ({
  statusCode,
  headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  body: JSON.stringify(body),
});

const str = (v, max) => String(v == null ? '' : v).trim().slice(0, max);

const WANTS = {
  email: 'A follow-up email',
  call: 'A follow-up call',
  email_list: 'Join the email list',
  bot: 'Talk with the Upstate Diving bot',
};

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') return json(405, { success: false, error: 'Method not allowed.' });
  if ((event.body || '').length > MAX_BODY) return json(413, { success: false, error: 'That submission is too large.' });

  let d;
  try { d = JSON.parse(event.body || '{}'); } catch { return json(400, { success: false, error: 'Invalid request.' }); }
  if (!d || typeof d !== 'object' || Array.isArray(d)) return json(400, { success: false, error: 'Invalid request.' });

  const filledMs = Date.now() - Number(d.loaded_at);
  if (str(d.website, 200) || !Number.isFinite(filledMs) || filledMs < MIN_FILL_MS) {
    return json(200, { success: true });
  }

  const row = {
    parent_first_name: str(d.parent_first_name, 80),
    parent_last_name:  str(d.parent_last_name, 80),
    parent_email:      str(d.parent_email, 254).toLowerCase(),
    parent_phone:      str(d.parent_phone, 40),
    contact_preference: str(d.contact_preference, 20),
  };

  const missing = [];
  if (!row.parent_first_name) missing.push('your first name');
  if (!row.parent_last_name) missing.push('your last name');
  if (!row.parent_email) missing.push('your email address');
  if (missing.length) return json(400, { success: false, error: `Please enter ${missing.join(', ')}.` });
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(row.parent_email)) {
    return json(400, { success: false, error: 'That email address does not look right.' });
  }
  if (!WANTS[row.contact_preference]) {
    return json(400, { success: false, error: 'Please choose how you would like to connect.' });
  }
  if (row.contact_preference === 'call' && !row.parent_phone) {
    return json(400, { success: false, error: 'Please enter a phone number so we can call you.' });
  }

  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    console.error('crm-info: SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is not set');
    return json(500, { success: false, error: 'This form is temporarily unavailable. Please email or call us instead.' });
  }

  try {
    const res = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/rpc/crm_public_inquiry`, {
      method: 'POST',
      headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p: row }),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      console.error('crm-info: database error', res.status, text);
      if (text.includes('busy')) {
        return json(503, { success: false, error: 'We are receiving a lot of requests right now. Please try again in a few minutes.' });
      }
      return json(500, { success: false, error: 'Something went wrong. Please try again, or email or call us.' });
    }
    let result = null;
    try { result = JSON.parse(await res.text()); } catch { result = null; }
    await notifyCoach({
      subject: `Information request: ${row.parent_first_name} ${row.parent_last_name} (Upstate Diving CRM)`,
      heading: 'Information request',
      leadId: result && result.lead_id,
      replyTo: row.parent_email,
      rows: [
        ['Name', `${row.parent_first_name} ${row.parent_last_name}`],
        ['Email', row.parent_email],
        ['Phone', row.parent_phone],
        ['Would like', WANTS[row.contact_preference]],
      ],
    });
    return json(200, { success: true });
  } catch (err) {
    console.error('crm-info: request failed', err.message);
    return json(500, { success: false, error: 'Something went wrong. Please try again, or email or call us.' });
  }
};
