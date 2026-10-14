// =============================================
// Netlify Function — public sign-up form -> DiveCRM.
// signup.html posts here; this validates the submission and calls the
// crm_public_signup database function (supabase-migration-v59.sql), which is
// executable by the service role only. The CRM tables stay closed to the
// public anon key.
//
// Required Netlify environment variables:
//   SUPABASE_URL               — already set (used by the build)
//   SUPABASE_SERVICE_ROLE_KEY  — Supabase -> Project Settings -> API ->
//                                service_role key. SECRET: never put it in
//                                js/config.js or any client-side file.
// =============================================

const { notifyCoach } = require('./lib/notify.js');
const { processDue } = require('./lib/mailer.js');
const { VERSION, TEXT } = require('./lib/release.js');

const MIN_FILL_MS = 4000;
const MAX_BODY = 30000;

const json = (statusCode, body) => ({
  statusCode,
  headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  body: JSON.stringify(body),
});

const str = (v, max) => String(v == null ? '' : v).trim().slice(0, max);

exports.handler = async (event) => {
  if (event.httpMethod === 'GET') {
    return json(200, { success: true, release_version: VERSION, release_text: TEXT });
  }
  if (event.httpMethod !== 'POST') {
    return json(405, { success: false, error: 'Method not allowed.' });
  }
  if ((event.body || '').length > MAX_BODY) {
    return json(413, { success: false, error: 'That submission is too large.' });
  }

  let d;
  try {
    d = JSON.parse(event.body || '{}');
  } catch {
    return json(400, { success: false, error: 'Invalid request.' });
  }
  if (!d || typeof d !== 'object' || Array.isArray(d)) {
    return json(400, { success: false, error: 'Invalid request.' });
  }

  // Bots fill the hidden field or submit instantly; answer "success" so they learn nothing.
  const filledMs = Date.now() - Number(d.loaded_at);
  if (str(d.website, 200) || !Number.isFinite(filledMs) || filledMs < MIN_FILL_MS) {
    return json(200, { success: true });
  }

  const row = {
    first_name:        str(d.first_name, 80),
    last_name:         str(d.last_name, 80),
    date_of_birth:     str(d.date_of_birth, 10),
    gender:            str(d.gender, 10),
    school_district:   str(d.school_district, 160),
    graduation_year:   str(d.graduation_year, 4),
    parent_first_name: str(d.parent_first_name, 80),
    parent_last_name:  str(d.parent_last_name, 80),
    parent_email:      str(d.parent_email, 254).toLowerCase(),
    parent_phone:      str(d.parent_phone, 40),
    street_address:    str(d.street_address, 200),
    city:              str(d.city, 100),
    zip_code:          str(d.zip_code, 20),
    emergency_contact_name:  str(d.emergency_contact_name, 160),
    emergency_contact_phone: str(d.emergency_contact_phone, 40),
    allergies_medical:       str(d.allergies_medical, 2000),
    prior_diving_experience:     str(d.prior_diving_experience, 40),
    prior_gymnastics_experience: str(d.prior_gymnastics_experience, 40),
    diving_location:  str(d.diving_location, 160),
    aau_number:       str(d.aau_number, 60),
    participates_in_competitions: str(d.participates_in_competitions, 5).toLowerCase(),
    source:           str(d.source, 100),
    referred_by:      str(d.referred_by, 160),
  };

  const signedName = str(d.signed_name, 160);
  const missing = [];
  if (!row.first_name) missing.push("the diver's first name");
  if (!row.last_name) missing.push("the diver's last name");
  if (!row.date_of_birth) missing.push("the diver's birthdate");
  if (!row.parent_first_name) missing.push('the parent/guardian first name');
  if (!row.parent_last_name) missing.push('the parent/guardian last name');
  if (!row.parent_email) missing.push('an email address');
  if (!row.parent_phone) missing.push('a phone number');
  if (!row.emergency_contact_name) missing.push('an emergency contact name');
  if (!row.emergency_contact_phone) missing.push('an emergency contact phone number');
  if (!row.aau_number) missing.push('the AAU membership number');
  const signedName = str(d.signed_name, 160);
  if (missing.length) {
    return json(400, { success: false, error: `Please enter ${missing.join(', ')}.` });
  }

  if (d.agree !== true) {
    return json(400, { success: false, error: 'Please tick the box to agree to the photo release and waiver.' });
  }
  if (signedName.length < 2) {
    return json(400, { success: false, error: 'Please type your full name to sign the photo release and waiver.' });
  }

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(row.parent_email)) {
    return json(400, { success: false, error: 'That email address does not look right.' });
  }
  const dob = new Date(row.date_of_birth + 'T00:00:00Z');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(row.date_of_birth) || isNaN(dob.getTime()) ||
      dob > new Date() || dob < new Date('1920-01-01T00:00:00Z')) {
    return json(400, { success: false, error: "That birthdate does not look right." });
  }
  if (row.graduation_year) {
    const y = Number(row.graduation_year);
    if (!Number.isInteger(y) || y < 2000 || y > 2100) {
      return json(400, { success: false, error: 'High school graduation year should be a four-digit year.' });
    }
  }
  const EXPERIENCE = ['None', 'Some Training', 'Extensive Training'];
  for (const k of ['prior_diving_experience', 'prior_gymnastics_experience']) {
    if (row[k].toLowerCase() === 'extensive experience') row[k] = 'Extensive Training';
    row[k] = EXPERIENCE.find(o => o.toLowerCase() === row[k].toLowerCase()) || '';
  }
  row.diving_location = ['RIT', 'Canandaigua'].find(o => o.toLowerCase() === row.diving_location.toLowerCase()) || '';
  if (row.participates_in_competitions && !['yes', 'no', 'maybe'].includes(row.participates_in_competitions)) {
    row.participates_in_competitions = '';
  }

  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    console.error('crm-signup: SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is not set');
    return json(500, { success: false, error: 'Sign-up is temporarily unavailable. Please email or call us instead.' });
  }

  try {
    const res = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/rpc/crm_public_signup`, {
      method: 'POST',
      headers: {
        apikey: key,
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ p: Object.assign({}, row, {
        signed_name: signedName,
        release_version: VERSION,
        release_text: TEXT,
        ip: str((event.headers || {})['x-nf-client-connection-ip'] ||
          String((event.headers || {})['x-forwarded-for'] || '').split(',')[0], 64),
        ua: str((event.headers || {})['user-agent'], 400),
      }) }),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      console.error('crm-signup: database error', res.status, text);
      if (text.includes('busy')) {
        return json(503, { success: false, error: 'We are receiving a lot of sign-ups right now. Please try again in a few minutes.' });
      }
      return json(500, { success: false, error: 'Something went wrong saving your sign-up. Please try again, or email or call us.' });
    }
    let result = null;
    try { result = JSON.parse(await res.text()); } catch { result = null; }
    if (result && (result.created === true || result.registered === true)) {
      await notifyCoach({
        subject: `${result.created ? 'New sign-up' : 'Registered'}: ${row.first_name} ${row.last_name} (Upstate Diving CRM)`,
        heading: result.created ? 'New sign-up' : 'Registered',
        leadId: result.lead_id,
        replyTo: row.parent_email,
        rows: [
          ['Diver', `${row.first_name} ${row.last_name}`],
          ['Parent / guardian', `${row.parent_first_name} ${row.parent_last_name}`],
          ['Email', row.parent_email],
          ['Phone', row.parent_phone],
          ['Diving location', row.diving_location],
          ['AAU number', row.aau_number],
          ['Found us through', row.source],
        ],
      });
      // The family's confirmation email (any enabled "after sign-up" template);
      // the 10-minute scheduler retries it if this attempt fails.
      if (result.created) await processDue({ leadId: result.lead_id });
    }
    return json(200, { success: true });
  } catch (err) {
    console.error('crm-signup: request failed', err.message);
    return json(500, { success: false, error: 'Something went wrong saving your sign-up. Please try again, or email or call us.' });
  }
};
