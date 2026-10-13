// =============================================
// Netlify scheduled function — sends the CRM's time-based automatic emails.
// Runs every 10 minutes (schedule in netlify.toml; scheduled functions only run
// on the published production deploy). Which emails are due is decided in the
// database (crm_email_due, supabase-migration-v65.sql); a given template is
// never sent twice to the same contact.
// =============================================

const { processDue } = require('./lib/mailer.js');

exports.handler = async () => {
  const r = await processDue();
  if (r.sent || r.skipped || r.failed) console.log('crm-email-scheduler:', JSON.stringify(r));
  return { statusCode: 200, body: JSON.stringify(r) };
};
