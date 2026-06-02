const BASE_ID  = process.env.AIRTABLE_BASE_ID;
const API_KEY  = process.env.AIRTABLE_API_KEY;
const TABLE    = process.env.AIRTABLE_SKILLS_TABLE ?? 'Skills';
const BASE_URL = `https://api.airtable.com/v0/${BASE_ID}`;

exports.handler = async (event) => {
  const { op, level, id } = event.queryStringParameters ?? {};

  try {
    if (op === 'skill' && id) {
      const record = await airtableFetch(`${encodeURIComponent(TABLE)}/${id}`);
      return ok(normalize(record));
    }

    if (op === 'level' && level !== undefined) {
      const formula = encodeURIComponent(`{# Skill Level} = ${level}`);
      const data = await airtableFetch(
        `${encodeURIComponent(TABLE)}?filterByFormula=${formula}&sort[0][field]=Skill+Name&sort[0][direction]=asc`
      );
      return ok((data.records ?? []).map(normalize));
    }

    // Default: all skills with Airtable pagination
    const records = await fetchAll();
    return ok(records);

  } catch (err) {
    return { statusCode: 500, body: JSON.stringify({ error: err.message }) };
  }
};

async function fetchAll() {
  let allRecords = [];
  let offset = null;
  do {
    const params = new URLSearchParams({
      pageSize:            '100',
      'sort[0][field]':    '# Skill Level',
      'sort[0][direction]':'asc',
      'sort[1][field]':    'Skill Name',
      'sort[1][direction]':'asc',
    });
    if (offset) params.set('offset', offset);
    const data = await airtableFetch(`${encodeURIComponent(TABLE)}?${params}`);
    allRecords = allRecords.concat(data.records ?? []);
    offset = data.offset ?? null;
  } while (offset);
  return allRecords.map(normalize);
}

async function airtableFetch(path) {
  const res = await fetch(`${BASE_URL}/${path}`, {
    headers: { Authorization: `Bearer ${API_KEY}` },
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body?.error?.message ?? `Airtable error ${res.status}`);
  }
  return res.json();
}

function normalize(record) {
  const f = record.fields ?? {};
  return {
    id:            record.id,
    name:          f['Skill Name']        ?? 'Untitled Skill',
    level:         f['# Skill Level']     ?? null,
    type:          f['Skill Type']        ?? 'General',
    description:   f['Skill Description'] ?? '',
    category:      f['Skill Category']    ?? '',
    videoUrl:      f['Video URL']         ?? null,
    coachingNotes: f['Coaching Notes']    ?? '',
  };
}

function ok(data) {
  return {
    statusCode: 200,
    headers:    { 'Content-Type': 'application/json' },
    body:       JSON.stringify(data),
  };
}
