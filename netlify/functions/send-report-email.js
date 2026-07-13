// =============================================
// Netlify Function — email a Dive Drills test report PDF to a diver's parent.
// Sends via Brevo's REST API (not SMTP) so we can attach the PDF directly.
//
// Required Netlify environment variable:
//   BREVO_API_KEY      — Brevo transactional API key
// Optional (defaults shown):
//   BREVO_SENDER_EMAIL — must be a verified sender in your Brevo account
//   BREVO_SENDER_NAME  — display name for the "from" address
//
// Safety: this function only ever emails the PARENT address passed in by the
// caller. The diver's own email is never used here — coaches don't get
// direct email contact with a minor athlete through this feature.
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

  const { parentEmail, parentName, diverName, level, coachName, coachMessage, pdfBase64, fileName } = payload;

  if (!parentEmail || !diverName || !level || !pdfBase64 || !fileName) {
    return { statusCode: 400, body: JSON.stringify({ success: false, error: 'Missing required fields.' }) };
  }

  const senderEmail = process.env.BREVO_SENDER_EMAIL || 'noreply@divedrills.com';
  const senderName  = process.env.BREVO_SENDER_NAME  || 'Dive Drills';

  const greeting = parentName ? `Hi ${escapeHtml(parentName)},` : 'Hi,';
  const messageParagraph = coachMessage
    ? `<p style="white-space:pre-wrap">${escapeHtml(coachMessage)}</p>`
    : '';

  const htmlContent = `
    <div style="font-family:Helvetica,Arial,sans-serif;color:#1a1a1a;line-height:1.6">
      <p>${greeting}</p>
      <p>Attached is ${escapeHtml(diverName)}'s Level ${escapeHtml(String(level))} test report from Dive Drills.</p>
      ${messageParagraph}
      <p>— ${escapeHtml(coachName || 'Your coach')}</p>
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
        to:      [{ email: parentEmail, name: parentName || undefined }],
        subject: `Dive Drills Test Report — ${diverName} Level ${level}`,
        htmlContent,
        attachment: [{ content: pdfBase64, name: fileName }],
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
