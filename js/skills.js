// =============================================
// DIVE DRILLS — Skills Library (Supabase)
// Reads from the public.skills table.
// No external API dependencies.
// =============================================

const Skills = {

  // ---- Fetch all skills, ordered by curriculum order ----
  async getAll() {
    const { data, error } = await window.supabaseClient
      .from('skills')
      .select('*')
      .is('deleted_at', null)
      .order('skill_order', { ascending: true })
      .order('skill_level', { ascending: true })
      .order('skill_name',  { ascending: true });
    if (error) throw new Error(error.message);
    return (data ?? []).map(Skills._normalize);
  },

  // ---- Fetch skills for a single level, ordered by curriculum order ----
  async getByLevel(level) {
    const { data, error } = await window.supabaseClient
      .from('skills')
      .select('*')
      .eq('skill_level', level)
      .is('deleted_at', null)
      .order('skill_order', { ascending: true })
      .order('skill_name',  { ascending: true });
    if (error) throw new Error(error.message);
    return (data ?? []).map(Skills._normalize);
  },

  // ---- Fetch a single skill by id ----
  async getById(id) {
    const { data, error } = await window.supabaseClient
      .from('skills')
      .select('*')
      .eq('id', id)
      .is('deleted_at', null)
      .single();
    if (error) throw new Error(error.message);
    return Skills._normalize(data);
  },

  // ---- Update a skill (coach only — enforced by RLS) ----
  async update(id, fields) {
    const { error } = await window.supabaseClient
      .from('skills')
      .update(Skills._blankOptionalFields(fields))
      .eq('id', id);
    if (error) throw new Error(error.message);
  },

  // ---- Convert null to '' for optional text columns that are NOT NULL ----
  _blankOptionalFields(fields) {
    const result = { ...fields };
    ['skill_description', 'coaching_notes', 'photo_url', 'video_url'].forEach(key => {
      if (key in result && result[key] == null) result[key] = '';
    });
    return result;
  },

  // ---- Get the next auto-assigned order number for a new skill ----
  // Returns the highest skill_order >= 10000, plus 10 (or 10000 if none exist).
  async getNextOrder() {
    const { data, error } = await window.supabaseClient
      .from('skills')
      .select('skill_order')
      .gte('skill_order', 10000)
      .is('deleted_at', null)
      .order('skill_order', { ascending: false })
      .limit(1);
    if (error) throw new Error(error.message);
    const highest = data?.length ? data[0].skill_order : 9990;
    return highest + 10;
  },

  // ---- Create a new skill (coach only — enforced by RLS) ----
  async create(fields) {
    const { data, error } = await window.supabaseClient
      .from('skills')
      .insert(Skills._blankOptionalFields(fields))
      .select()
      .single();
    if (error) throw new Error(error.message);
    return Skills._normalize(data);
  },

  // ---- Normalize a DB row into a clean skill object ----
  _normalize(row) {
    return {
      id:              row.id,
      name:            row.skill_name,
      level:           row.skill_level,
      order:           row.skill_order,
      type:            row.skill_type        || 'General',
      description:     row.skill_description || '',
      category:        row.skill_category    || '',
      videoUrl:        row.video_url         || null,
      photoUrl:        row.photo_url         || null,
      coachingNotes:   row.coaching_notes    || '',
      requiresHarness: row.requires_harness  || false,
      isTestable:      row.is_testable       !== false,
    };
  },

  // ---- Client-side filtering (no extra DB round-trips) ----
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

  // ---- Helpers for filter dropdowns ----
  uniqueLevels(skills) {
    return [...new Set(skills.map(s => s.level).filter(v => v !== null))].sort((a, b) => a - b);
  },
  uniqueTypes(skills) {
    return [...new Set(skills.map(s => s.type).filter(Boolean))].sort();
  },
  uniqueCategories(skills) {
    return [...new Set(skills.map(s => s.category).filter(Boolean))].sort();
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
