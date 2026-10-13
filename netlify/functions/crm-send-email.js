// =============================================
// Netlify Function — a coach previews, tests or sends a CRM email template.
// The browser sends the coach's Supabase login token; the function proves the
// caller is an active coach by running crm_email_prepare AS THAT COACH (it
// raises for anyone else), then sends through Brevo and logs it with the
// service role.
//
// POST { action: 'preview' | 'test' | 'send', template_id, lead_id? }
//   preview  -> the rendered subject/body for that contact (nothing sent)
//   send may carry the coach's edited `subject` and `body`; those exact words are
//   sent. Anything still containing a [[marker]] is refused.
//   test     -> sends the template, with sample names, to the coach's own address
//   send     -> sends it to the contact's parent now and logs it on the timeline
// Needs SUPABASE_URL and SUPABASE_ANON_KEY (already set for the build) plus the
// variables listed in lib/mailer.js.
// =============================================

const { render, varsFor, sendEmail, record, siteUrl, hasMarkers } = require('./lib/mailer.js');

const json = (statusCode, body) => ({
  statusCode,
  headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  body: JSON.stringify(body),
});

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const SAMPLE = {
  parent_first_name: 'Pat', parent_name: 'Pat Lee', diver_first_name: 'Sam', diver_name: 'Sam Lee',
  diving_location: 'RIT', trial_date: 'Saturday, November 8',
};

async function prepareAsCoach(jwt, templateId, leadId) {
  const url = process.env.SUPABASE_URL;
  const anon = process.env.SUPABASE_ANON_KEY;
  if (!url || !anon) throw Object.assign(new Error('Email sending is not configured.'), { status: 500 });
  const res = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/rpc/crm_email_prepare`, {
    method: 'POST',
    headers: { apikey: anon, Authorization: `Bearer ${jwt}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ p_template_id: templateId, p_lead_id: leadId || null }),
    signal: AbortSignal.timeout(8000),
  });
  const text = await res.text().catch(() => '');
  if (!res.ok) {
    let msg = 'Not allowed.';
    try { msg = JSON.parse(text).message || msg; } catch { /* keep default */ }
    throw Object.assign(new Error(msg), { status: res.status === 401 ? 401 : 403 });
  }
  return JSON.parse(text);
}

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') return json(405, { success: false, error: 'Method not allowed.' });

  const auth = (event.headers && (event.headers.authorization || event.headers.Authorization)) || '';
  const jwt = auth.replace(/^Bearer\s+/i, '').trim();
  if (!jwt) return json(401, { success: false, error: 'Please sign in again.' });

  let d;
  try { d = JSON.parse(event.body || '{}'); } catch { return json(400, { success: false, error: 'Invalid request.' }); }
  const action = d && d.action;
  if (!['preview', 'test', 'send'].includes(action) || !UUID.test(String(d.template_id || ''))) {
    return json(400, { success: false, error: 'Invalid request.' });
  }
  const leadId = d.lead_id ? String(d.lead_id) : null;
  if (leadId && !UUID.test(leadId)) return json(400, { success: false, error: 'Invalid request.' });
  if ((action === 'preview' || action === 'send') && !leadId) {
    return json(400, { success: false, error: 'Choose a contact first.' });
  }

  try {
    const p = await prepareAsCoach(jwt, d.template_id, action === 'test' ? null : leadId);
    const t = p.template;

    if (action === 'test') {
      if (!p.coach_email) return json(400, { success: false, error: 'Your profile has no email address.' });
      const vars = Object.assign({}, SAMPLE, { followup_link: `${siteUrl()}/followup?t=SAMPLE-LINK-NOT-ACTIVE` });
      const r = await sendEmail({ to: p.coach_email, subject: `[TEST] ${render(t.subject, vars)}`, text: render(t.body, vars), diver: 'Sam' });
      return r.ok ? json(200, { success: true, sent_to: p.coach_email })
        : json(502, { success: false, error: 'The email service refused it. ' + r.error });
    }

    const v = p.vars || {};
    const vars = varsFor(v);
    let subject = render(t.subject, vars);
    let text = render(t.body, vars);

    if (action === 'preview') {
      return json(200, { success: true, to: v.to_email || null, do_not_contact: !!v.do_not_contact, subject, body: text });
    }

    if (d.subject != null || d.body != null) {
      subject = String(d.subject == null ? '' : d.subject).trim();
      text = String(d.body == null ? '' : d.body).replace(/\r\n/g, '\n').trim();
      if (!subject || !text) return json(400, { success: false, error: 'The subject and message cannot be empty.' });
      if (subject.length > 300 || text.length > 20000) return json(400, { success: false, error: 'That email is too long.' });
    }
    if (hasMarkers(subject) || hasMarkers(text)) {
      return json(400, { success: false, error: 'Fill in every [[ ]] part before sending.' });
    }

    if (!v.to_email) return json(400, { success: false, error: 'This contact has no parent email address.' });
    if (v.do_not_contact) return json(400, { success: false, error: 'This contact is marked do not contact.' });

    const r = await sendEmail({ to: v.to_email, subject, text, diver: v.diver_first_name });
    const row = { template_id: t.id, lead_id: leadId };
    if (!r.ok) {
      await record(row, v.to_email, subject, 'failed', r.error, false, p.coach_id).catch(() => {});
      return json(502, { success: false, error: 'The email service refused it. ' + r.error });
    }
    await record(row, v.to_email, subject, 'sent', null, false, p.coach_id).catch((e) =>
      console.error('crm-send-email: log failed', e.message));
    return json(200, { success: true, sent_to: v.to_email });
  } catch (err) {
    console.error('crm-send-email:', err.message);
    return json(err.status || 500, { success: false, error: err.status === 403 ? 'Only coaches can send email.' : err.message });
  }
};
