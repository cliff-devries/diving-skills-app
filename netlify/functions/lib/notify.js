// Emails the coach about CRM events through Brevo (same account as send-report-email.js).
// Never throws: the sign-up or registration is already saved, so a failed email only logs.
//
// Netlify env vars: BREVO_API_KEY (required), BREVO_SENDER_EMAIL / BREVO_SENDER_NAME
// (sender must be verified in Brevo), NOTIFY_EMAIL (default cliff@upstatediving.com).

const DEFAULT_TO = 'cliff@upstatediving.com';

const esc = (s) => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function siteUrl() {
  return (process.env.URL || 'https://divedrills.com').replace(/\/+$/, '');
}

async function notifyCoach({ subject, heading, rows, leadId, replyTo }) {
  try {
    const apiKey = process.env.BREVO_API_KEY;
    if (!apiKey) {
      console.error('notify: BREVO_API_KEY is not set, no email sent');
      return false;
    }
    const link = leadId ? `${siteUrl()}/crm.html#lead/${encodeURIComponent(leadId)}` : '';
    const shown = rows.filter(([, v]) => v);
    const html = `<div style="font-family:Arial,sans-serif;font-size:15px;color:#020202">
      <h2 style="margin:0 0 12px">${esc(heading)}</h2>
      <table cellpadding="4" style="border-collapse:collapse">${shown.map(([k, v]) =>
        `<tr><td style="color:#707070;padding-right:14px">${esc(k)}</td><td>${esc(v)}</td></tr>`).join('')}</table>
      ${link ? `<p style="margin-top:16px"><a href="${esc(link)}">Open in the CRM</a></p>` : ''}</div>`;
    const text = `${heading}\n\n${shown.map(([k, v]) => `${k}: ${v}`).join('\n')}${link ? `\n\nOpen in the CRM: ${link}` : ''}`;

    const body = {
      sender: {
        name: process.env.BREVO_SENDER_NAME || 'Upstate Diving CRM',
        email: process.env.BREVO_SENDER_EMAIL || 'noreply@divedrills.com',
      },
      to: [{ email: process.env.NOTIFY_EMAIL || DEFAULT_TO }],
      subject: String(subject).replace(/[\r\n]+/g, ' '),
      htmlContent: html,
      textContent: text,
    };
    if (replyTo && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(replyTo)) body.replyTo = { email: replyTo };

    const res = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': apiKey, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(6000),
    });
    if (!res.ok) {
      console.error('notify: Brevo refused the email', res.status, await res.text().catch(() => ''));
      return false;
    }
    return true;
  } catch (err) {
    console.error('notify: failed', err.message);
    return false;
  }
}

module.exports = { notifyCoach };
