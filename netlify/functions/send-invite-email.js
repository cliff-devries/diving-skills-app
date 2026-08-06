// =============================================
// Netlify Function — email a Dive Drills parent/family account invite link.
// Sends via Brevo's REST API, matching send-report-email.js.
//
// Required Netlify environment variable:
//   BREVO_API_KEY      — Brevo transactional API key
// Optional (defaults shown):
//   BREVO_SENDER_EMAIL — must be a verified sender in your Brevo account
//   BREVO_SENDER_NAME  — display name for the "from" address
// =============================================

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: JSON.stringify({ success: false, error: 'Method not allowed.' }) };
  }

  const apiKey = process.env.BREVO_API_KEY;
  if (!apiKey) {
    return { statusCode: 500, body: JSON.stringify({ success: false, error: 'Email service is not configured (missing BREVO_API_KEY).' }) };
  }

  let payload;
  try {
    payload = JSON.parse(event.body || '{}');
  } catch {
    return { statusCode: 400, body: JSON.stringify({ success: false, error: 'Invalid request body.' }) };
  }

  const { parentEmail, diverName, inviteLink, coachName } = payload;

  if (!parentEmail || !diverName || !inviteLink) {
    return { statusCode: 400, body: JSON.stringify({ success: false, error: 'Missing required fields.' }) };
  }

  const senderEmail = process.env.BREVO_SENDER_EMAIL || 'noreply@divedrills.com';
  const senderName  = process.env.BREVO_SENDER_NAME  || 'Dive Drills';

  const htmlContent = `
    <div style="font-family:Helvetica,Arial,sans-serif;color:#1a1a1a;line-height:1.6">
      <p>Hi,</p>
      <p>${escapeHtml(coachName || 'Your coach')} has invited you to create a Dive Drills family account for
      ${escapeHtml(diverName)}. This account gives you and your diver access to track progress, view skills,
      and stay connected with the coaching staff.</p>
      <p><a href="${escapeHtml(inviteLink)}" style="display:inline-block;padding:10px 20px;background:#00c9a7;color:#0f0f0f;font-weight:700;text-decoration:none;border-radius:6px">Set Up Your Account</a></p>
      <p style="color:#666666;font-size:12px">Or copy and paste this link into your browser:<br>${escapeHtml(inviteLink)}</p>
      <p style="color:#666666;font-size:12px">This link expires in 7 days and can only be used once.</p>
      <p style="color:#666666;font-size:12px;margin-top:24px">Sent via Dive Drills — divedrills.com</p>
    </div>`;

  try {
    const res = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: {
        'api-key':      apiKey,
        'Content-Type': 'application/json',
        'Accept':       'application/json',
      },
      body: JSON.stringify({
        sender:  { name: senderName, email: senderEmail },
        to:      [{ email: parentEmail }],
        subject: `You're invited to Dive Drills — ${diverName}`,
        htmlContent,
      }),
    });

    if (!res.ok) {
      const errBody = await res.text().catch(() => '');
      return { statusCode: 502, body: JSON.stringify({ success: false, error: `Brevo API error (${res.status}): ${errBody}` }) };
    }

    return { statusCode: 200, body: JSON.stringify({ success: true }) };
  } catch (err) {
    return { statusCode: 500, body: JSON.stringify({ success: false, error: err.message }) };
  }
};

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
