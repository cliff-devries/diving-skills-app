// =============================================
// DIVING SKILLS — Airtable API
// Read-only access to the skills library.
// Coaches edit skills directly in Airtable.
// =============================================

const Airtable = {

  get baseUrl() {
    return `https://api.airtable.com/v0/${CONFIG.AIRTABLE_BASE_ID}`;
  },

  get headers() {
    return {
      'Authorization': `Bearer ${CONFIG.AIRTABLE_API_KEY}`,
      'Content-Type':  'application/json',
    };
  },

  // ---- Internal fetch wrapper ----
  async _request(path) {
    const url = `${this.baseUrl}/${path}`;
    let res;
    try {
      res = await fetch(url, { headers: this.headers });
    } catch (networkErr) {
      throw new Error('Network error — check your connection and try again.');
    }
    if (!res.ok) {
      let body = {};
      try { body = await res.json(); } catch (_) { /* ignore */ }
      const msg = body?.error?.message ?? `Airtable responded with status ${res.status}`;
      throw new Error(msg);
    }
    return res.json();
  },

  // ---- Fetch ALL skills, handling Airtable's 100-record pagination ----
  async getAllSkills() {
    const table = encodeURIComponent(CONFIG.AIRTABLE_SKILLS_TABLE);
    let allRecords = [];
    let offset     = null;

    do {
      const params = new URLSearchParams();
      params.set('pageSize', '100');
      // Sort by level ascending, then name ascending
      params.set('sort[0][field]',     '# Skill Level');
      params.set('sort[0][direction]', 'asc');
      params.set('sort[1][field]',     'Skill Name');
      params.set('sort[1][direction]', 'asc');
      if (offset) params.set('offset', offset);

      const data = await this._request(`${table}?${params.toString()}`);
      allRecords = allRecords.concat(data.records ?? []);
      offset = data.offset ?? null;

    } while (offset);

    return allRecords.map(r => this._normalize(r));
  },

  // ---- Fetch skills for a specific level (0–12) ----
  async getSkillsByLevel(level) {
    const table   = encodeURIComponent(CONFIG.AIRTABLE_SKILLS_TABLE);
    const formula = encodeURIComponent(`{# Skill Level} = ${level}`);
    const data    = await this._request(
      `${table}?filterByFormula=${formula}&sort[0][field]=Skill+Name&sort[0][direction]=asc`
    );
    return (data.records ?? []).map(r => this._normalize(r));
  },

  // ---- Fetch a single skill record ----
  async getSkill(recordId) {
    const table = encodeURIComponent(CONFIG.AIRTABLE_SKILLS_TABLE);
    const data  = await this._request(`${table}/${recordId}`);
    return this._normalize(data);
  },

  // ---- Normalize an Airtable record into a clean JS object ----
  _normalize(record) {
    const f = record.fields ?? {};
    return {
      id:            record.id,
      name:          f['Skill Name']        ?? 'Untitled Skill',
      level:         f['# Skill Level']     ?? null,
      type:          f['Skill Type']         ?? 'General',
      description:   f['Skill Description'] ?? '',
      category:      f['Skill Category']    ?? '',
      videoUrl:      f['Video URL']         ?? null,
      coachingNotes: f['Coaching Notes']    ?? '',
    };
  },

  // ---- Client-side filtering (fast, no extra API calls) ----
  filterSkills(skills, { level, type, category, search } = {}) {
    return skills.filter(skill => {
      if (level !== null && level !== undefined && level !== '') {
        if (skill.level !== Number(level)) return false;
      }
      if (type     && skill.type     !== type)     return false;
      if (category && skill.category !== category) return false;
      if (search) {
        const q = search.toLowerCase();
        const hit = skill.name.toLowerCase().includes(q)
                 || skill.description.toLowerCase().includes(q)
                 || skill.type.toLowerCase().includes(q);
        if (!hit) return false;
      }
      return true;
    });
  },

  // ---- Helpers for populating filter dropdowns ----
  uniqueTypes(skills) {
    return [...new Set(skills.map(s => s.type).filter(Boolean))].sort();
  },
  uniqueCategories(skills) {
    return [...new Set(skills.map(s => s.category).filter(Boolean))].sort();
  },
  uniqueLevels(skills) {
    return [...new Set(skills.map(s => s.level).filter(v => v !== null))].sort((a, b) => a - b);
  },

  // ---- Group skills by level ----
  groupByLevel(skills) {
    const groups = {};
    skills.forEach(skill => {
      const lvl = skill.level ?? 'Other';
      if (!groups[lvl]) groups[lvl] = [];
      groups[lvl].push(skill);
    });
    return groups;
  },
};
