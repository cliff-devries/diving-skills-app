// =============================================
// Netlify Function — DiveSignUp write API.
// All mutations (create/edit/delete activity, item, signup) go here.
// The organizer password is checked server-side; the service_role key
// never reaches the browser.
//
// Required env vars:
//   SUPABASE_URL              — project URL
//   SUPABASE_SERVICE_ROLE_KEY — service_role key (never expose client-side)
//   SIGNUP_ORGANIZER_PASSWORD — the organizer password (set in Netlify env)
//   BREVO_API_KEY             — for confirmation emails (optional — email skipped if unset)
//   BREVO_SENDER_EMAIL        — verified Brevo sender
//   BREVO_SENDER_NAME         — display name for sender (optional)
//   URL                       — set automatically by Netlify; used for cancel links
// =============================================

const MAX_BODY = 20000;
const str = (v, max) => String(v == null ? '' : v).trim().slice(0, max);
const int = (v, def = 1) => { const n = parseInt(v, 10); return Number.isFinite(n) && n >= 1 ? n : def; };

const json = (code, body) => ({
  statusCode: code,
  headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  body: JSON.stringify(body),
});

function db(url, key) {
  const base = url.replace(/\/+$/, '') + '/rest/v1';
  const headers = {
    apikey: key,
    Authorization: `Bearer ${key}`,
    'Content-Type': 'application/json',
    Prefer: 'return=representation',
  };

  async function req(method, path, body) {
    const res = await fetch(base + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
    const text = await res.text().catch(() => '');
    if (!res.ok) throw new Error(`DB ${res.status}: ${text.slice(0, 200)}`);
    return text ? JSON.parse(text) : null;
  }

  return {
    get:    (path)         => req('GET', path),
    post:   (path, body)   => req('POST', path, body),
    patch:  (path, body)   => req('PATCH', path, body),
    delete: (path)         => req('DELETE', path),
  };
}

async function sendConfirmation({ name, email, activityTitle, itemName, cancelUrl }) {
  const apiKey = process.env.BREVO_API_KEY;
  if (!apiKey || !email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return;
  const esc = s => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const html = `<div style="font-family:Arial,sans-serif;font-size:15px;color:#020202">
    <h2 style="margin:0 0 12px">You're signed up!</h2>
    <p>Hi ${esc(name)}, you're confirmed for:</p>
    <p style="margin:12px 0;font-weight:600">${esc(itemName)}</p>
    <p style="color:#555">Event: ${esc(activityTitle)}</p>
    <p style="margin-top:20px;font-size:0.9em;color:#888">
      Changed your mind? <a href="${esc(cancelUrl)}">Cancel your sign-up</a>
    </p></div>`;
  const text = `Hi ${name}, you're signed up for "${itemName}" at ${activityTitle}.\n\nCancel: ${cancelUrl}`;

  try {
    const res = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': apiKey, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        sender: {
          email: process.env.BREVO_SENDER_EMAIL || 'noreply@divedrills.com',
          name: process.env.BREVO_SENDER_NAME || 'Upstate Diving',
        },
        to: [{ email }],
        subject: `Sign-up confirmed: ${activityTitle}`,
        htmlContent: html,
        textContent: text,
      }),
      signal: AbortSignal.timeout(6000),
    });
    if (!res.ok) console.error('su-api: Brevo error', res.status, await res.text().catch(() => ''));
  } catch (err) {
    console.error('su-api: email failed', err.message);
  }
}

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') return json(405, { error: 'Method not allowed' });
  if ((event.body || '').length > MAX_BODY) return json(413, { error: 'Request too large' });

  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const orgPass = process.env.SIGNUP_ORGANIZER_PASSWORD;
  if (!url || !key) return json(500, { error: 'Server misconfigured' });

  let d;
  try { d = JSON.parse(event.body || '{}'); } catch { return json(400, { error: 'Invalid JSON' }); }

  const action = str(d.action, 40);
  const client = db(url, key);
  const siteUrl = (process.env.URL || 'https://divedrills.com').replace(/\/+$/, '');

  // ── Organizer-only actions ──────────────────────────────────
  const orgActions = new Set([
    'create_activity', 'update_activity', 'delete_activity',
    'create_item', 'update_item', 'delete_item',
    'delete_signup',   // organizer can remove any signup
  ]);

  if (orgActions.has(action)) {
    if (!orgPass || str(d.password, 200) !== orgPass) {
      return json(403, { error: 'Wrong organizer password' });
    }
  }

  try {
    // ── Activities ─────────────────────────────────────────────
    if (action === 'create_activity') {
      const row = {
        title:     str(d.title, 200),
        date:      str(d.date, 10) || null,
        time_text: str(d.time_text, 80) || null,
        location:  str(d.location, 200) || null,
        notes:     str(d.notes, 2000) || null,
      };
      if (!row.title) return json(400, { error: 'Title is required' });
      const [created] = await client.post('/su_activities', row);
      return json(200, { ok: true, activity: created });
    }

    if (action === 'update_activity') {
      const id = str(d.id, 36);
      if (!id) return json(400, { error: 'Missing id' });
      const row = {};
      if (d.title    !== undefined) row.title     = str(d.title, 200);
      if (d.date     !== undefined) row.date      = str(d.date, 10) || null;
      if (d.time_text !== undefined) row.time_text = str(d.time_text, 80) || null;
      if (d.location !== undefined) row.location  = str(d.location, 200) || null;
      if (d.notes    !== undefined) row.notes     = str(d.notes, 2000) || null;
      if (row.title !== undefined && !row.title) return json(400, { error: 'Title cannot be blank' });
      const [updated] = await client.patch(`/su_activities?id=eq.${encodeURIComponent(id)}`, row);
      return json(200, { ok: true, activity: updated });
    }

    if (action === 'delete_activity') {
      const id = str(d.id, 36);
      if (!id) return json(400, { error: 'Missing id' });
      await client.delete(`/su_activities?id=eq.${encodeURIComponent(id)}`);
      return json(200, { ok: true });
    }

    // ── Items ──────────────────────────────────────────────────
    if (action === 'create_item') {
      const row = {
        activity_id:  str(d.activity_id, 36),
        name:         str(d.name, 200),
        description:  str(d.description, 500) || null,
        spots_needed: int(d.spots_needed),
        sort_order:   int(d.sort_order, 0),
      };
      if (!row.activity_id || !row.name) return json(400, { error: 'activity_id and name are required' });
      const [created] = await client.post('/su_items', row);
      return json(200, { ok: true, item: created });
    }

    if (action === 'update_item') {
      const id = str(d.id, 36);
      if (!id) return json(400, { error: 'Missing id' });
      const row = {};
      if (d.name         !== undefined) row.name         = str(d.name, 200);
      if (d.description  !== undefined) row.description  = str(d.description, 500) || null;
      if (d.spots_needed !== undefined) row.spots_needed = int(d.spots_needed);
      if (d.sort_order   !== undefined) row.sort_order   = int(d.sort_order, 0);
      if (row.name !== undefined && !row.name) return json(400, { error: 'Name cannot be blank' });
      const [updated] = await client.patch(`/su_items?id=eq.${encodeURIComponent(id)}`, row);
      return json(200, { ok: true, item: updated });
    }

    if (action === 'delete_item') {
      const id = str(d.id, 36);
      if (!id) return json(400, { error: 'Missing id' });
      await client.delete(`/su_items?id=eq.${encodeURIComponent(id)}`);
      return json(200, { ok: true });
    }

    // ── Signups ────────────────────────────────────────────────
    if (action === 'create_signup') {
      const itemId = str(d.item_id, 36);
      const name   = str(d.name, 160);
      const email  = str(d.email, 254).toLowerCase() || null;
      const qty    = int(d.qty);
      const note   = str(d.note, 500) || null;

      if (!itemId || !name) return json(400, { error: 'item_id and name are required' });

      // Fetch item + current signups in one round-trip each, then check spots
      const [item]    = await client.get(`/su_items?id=eq.${encodeURIComponent(itemId)}&select=*`);
      if (!item) return json(404, { error: 'Item not found' });

      const existing  = await client.get(`/su_signups?item_id=eq.${encodeURIComponent(itemId)}&select=qty`);
      const taken     = (existing || []).reduce((s, r) => s + (r.qty || 1), 0);
      const available = item.spots_needed - taken;
      if (qty > available) {
        return json(409, { error: `Only ${available} spot${available === 1 ? '' : 's'} left` });
      }

      const [signup] = await client.post('/su_signups', {
        activity_id: item.activity_id,
        item_id: itemId,
        name,
        email,
        qty,
        note,
      });

      // Email confirmation
      if (email) {
        const [activity] = await client.get(`/su_activities?id=eq.${encodeURIComponent(item.activity_id)}&select=title`);
        const cancelUrl = `${siteUrl}/signup.html?cancel=${encodeURIComponent(signup.edit_token)}`;
        await sendConfirmation({
          name,
          email,
          activityTitle: activity?.title || 'the event',
          itemName: item.name,
          cancelUrl,
        });
      }

      return json(200, { ok: true, signup });
    }

    if (action === 'delete_signup') {
      // Organizer path — password already checked above
      const id = str(d.id, 36);
      if (!id) return json(400, { error: 'Missing id' });
      await client.delete(`/su_signups?id=eq.${encodeURIComponent(id)}`);
      return json(200, { ok: true });
    }

    if (action === 'cancel_signup') {
      // Parent self-cancel via edit_token (no password needed)
      const token = str(d.edit_token, 36);
      if (!token) return json(400, { error: 'Missing edit_token' });
      await client.delete(`/su_signups?edit_token=eq.${encodeURIComponent(token)}`);
      return json(200, { ok: true });
    }

    return json(400, { error: `Unknown action: ${action}` });
  } catch (err) {
    console.error('su-api error', err.message);
    return json(500, { error: 'Server error — please try again' });
  }
};
