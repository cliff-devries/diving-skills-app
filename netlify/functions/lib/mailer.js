// Shared email engine for the DiveCRM "Emails" feature.
//   render / toHtml  — fill {{placeholders}} and turn plain text into a simple HTML email
//   sendEmail        — one message through Brevo to a parent
//   processDue       — send every automatic email that has come due (optionally one lead only)
// Used by crm-email-scheduler.js (every 10 minutes), crm-signup.js (immediate
// confirmation) and crm-send-email.js (a coach sending by hand).
//
// Netlify env vars: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, BREVO_API_KEY,
// BREVO_SENDER_EMAIL (verified in Brevo), optional BREVO_SENDER_NAME,
// NOTIFY_EMAIL (reply-to address, default admin@upstatediving.com).

const REPLY_TO = () => process.env.NOTIFY_EMAIL || 'admin@upstatediving.com';
const siteUrl = () => (process.env.URL || 'https://divedrills.com').replace(/\/+$/, '');

const esc = (s) => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const KEYS = ['parent_first_name', 'parent_name', 'diver_first_name', 'diver_name',
  'diving_location', 'trial_date', 'followup_link'];

// A [[like this]] marks something still to be filled in; nothing containing one is ever sent.
const MARKER = /\[\[[^\]]*\]\]/;
const hasMarkers = (text) => MARKER.test(String(text == null ? '' : text));

// Details the CRM may not have become a [[marker]] to fill in; other unknown
// placeholders are removed rather than sent as raw {{text}}.
const NEEDS_FILL = { trial_date: '[[trial date]]', diving_location: '[[diving location]]' };
function render(text, vars) {
  return String(text == null ? '' : text).replace(/\{\{\s*([a-z_]+)\s*\}\}/g, (_, k) => {
    const v = vars && vars[k] != null ? String(vars[k]) : '';
    return v === '' && NEEDS_FILL[k] ? NEEDS_FILL[k] : v;
  });
}

function varsFor(row) {
  const v = Object.assign({}, row);
  v.followup_link = `${siteUrl()}/signup`;
  return v;
}

const FOOTER = (diver) => `You are receiving this email because ${diver || 'a diver'} was signed up with Upstate Diving. ` +
  'If you would rather not receive these messages, just reply and let us know.';

// Plain text in, simple HTML out: blank line = new paragraph, [Label](URL) and bare URLs become clickable.
// Splits each line into link tokens and plain-text segments so each part is escaped correctly.
function toHtml(text, diver) {
  const linkify = (s) => {
    const LINK = /\[([^\]]+)\]\((https?:\/\/[^)]+)\)|(https?:\/\/[^\s<]+)/g;
    let out = '';
    let last = 0;
    let m;
    while ((m = LINK.exec(s)) !== null) {
      out += esc(s.slice(last, m.index));
      if (m[1] != null) {
        out += `<a href="${esc(m[2])}">${esc(m[1])}</a>`;
      } else {
        const bare = m[3].match(/^(.*?)([.,;:!?)]*)$/);
        out += `<a href="${esc(bare[1])}">${esc(bare[1])}</a>${esc(bare[2])}`;
      }
      last = m.index + m[0].length;
    }
    out += esc(s.slice(last));
    return out;
  };
  const paras = String(text).replace(/\r\n/g, '\n').split(/\n{2,}/)
    .map((p) => `<p style="margin:0 0 14px">${linkify(p).replace(/\n/g, '<br>')}</p>`).join('');
  return `<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:1.55;color:#020202">${paras}` +
    `<p style="margin:24px 0 0;font-size:12px;color:#707070">${esc(FOOTER(diver))}</p></div>`;
}

async function sendEmail({ to, subject, text, diver }) {
  const apiKey = process.env.BREVO_API_KEY;
  if (!apiKey) return { ok: false, error: 'BREVO_API_KEY is not set' };
  try {
    const res = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': apiKey, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        sender: {
          name: process.env.BREVO_SENDER_NAME || 'Upstate Diving',
          email: process.env.BREVO_SENDER_EMAIL || 'noreply@divedrills.com',
        },
        to: [{ email: to }],
        replyTo: { email: REPLY_TO() },
        subject: String(subject).replace(/[\r\n]+/g, ' '),
        htmlContent: toHtml(text, diver),
        textContent: `${text}\n\n${FOOTER(diver)}`,
      }),
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) {
      const detail = await res.text().catch(() => '');
      return { ok: false, error: `Brevo ${res.status} ${detail}`.slice(0, 400) };
    }
    return { ok: true };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

async function serviceRpc(name, args) {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error('SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is not set');
  const res = await fetch(`${url.replace(/\/+$/, '')}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(args),
    signal: AbortSignal.timeout(8000),
  });
  const text = await res.text().catch(() => '');
  if (!res.ok) throw new Error(`${name} ${res.status} ${text}`.slice(0, 300));
  return text ? JSON.parse(text) : null;
}

const record = (row, to, subject, status, error, automatic, sentBy) =>
  serviceRpc('crm_email_record', {
    p_template_id: row.template_id, p_lead_id: row.lead_id, p_to: to || null, p_subject: subject || null,
    p_status: status, p_error: error || null, p_automatic: automatic, p_sent_by: sentBy || null,
  });

// Sends every automatic email that is due. Never throws.
async function processDue({ leadId } = {}) {
  const out = { sent: 0, skipped: 0, failed: 0 };
  try {
    const due = await serviceRpc('crm_email_due', { p_lead_id: leadId || null, p_limit: 40 });
    for (const row of due || []) {
      try {
        if (!row.to_email || row.do_not_contact) {
          await record(row, row.to_email, row.subject, 'skipped',
            row.do_not_contact ? 'Contact is marked do not contact' : 'No email address', true);
          out.skipped++;
          continue;
        }
        const vars = varsFor(row);
        const subject = render(row.subject, vars);
        const text = render(row.body, vars);
        if (hasMarkers(subject) || hasMarkers(text)) {
          console.error('mailer: not sending, still has [[ ]] to fill in:', row.template_name, row.lead_id);
          continue;
        }
        const sent = await sendEmail({ to: row.to_email, subject, text, diver: row.diver_first_name });
        if (sent.ok) {
          await record(row, row.to_email, subject, 'sent', null, true);
          out.sent++;
        } else {
          console.error('mailer: send failed', row.template_name, sent.error);
          await record(row, row.to_email, subject, 'failed', sent.error, true);
          out.failed++;
        }
      } catch (err) {
        console.error('mailer: item failed', err.message);
        out.failed++;
      }
    }
  } catch (err) {
    console.error('mailer: processDue failed', err.message);
  }
  return out;
}

module.exports = { hasMarkers, render, varsFor, toHtml, sendEmail, processDue, serviceRpc, record, KEYS, siteUrl };
