// =============================================
// DIVING SKILLS — Airtable API (via Netlify Function)
// All requests go through /.netlify/functions/airtable-skills
// so the Airtable API key never reaches the browser.
// =============================================

const Airtable = {

  async _request(params = {}) {
    const qs  = new URLSearchParams(params).toString();
    const url = `/.netlify/functions/airtable-skills${qs ? '?' + qs : ''}`;
    let res;
    try {
      res = await fetch(url);
    } catch (networkErr) {
      throw new Error('Network error — check your connection and try again.');
    }
    if (!res.ok) {
      let body = {};
      try { body = await res.json(); } catch (_) { /* ignore */ }
      throw new Error(body?.error ?? `Server responded with status ${res.status}`);
    }
    return res.json();
  },

  async getAllSkills() {
    return this._request({ op: 'all' });
  },

  async getSkillsByLevel(level) {
    return this._request({ op: 'level', level });
  },

  async getSkill(recordId) {
    return this._request({ op: 'skill', id: recordId });
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
