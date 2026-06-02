// =============================================
// DIVING SKILLS — Supabase Database Functions
// All database reads/writes go through this module.
// Uses the global `window.supabaseClient` set by config.js.
// =============================================

const SupabaseDB = {

  get db() { return window.supabaseClient; },

  // =============================================
  // PROFILES
  // =============================================

  async getProfile(userId) {
    const { data, error } = await this.db
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .single();
    if (error && error.code !== 'PGRST116') {
      console.error('[SupabaseDB] getProfile:', error.message);
    }
    return data ?? null;
  },

  async getProfileByEmail(email) {
    const { data, error } = await this.db
      .from('profiles')
      .select('id, full_name, email, role, avatar_url')
      .eq('email', email.trim().toLowerCase())
      .single();
    if (error && error.code !== 'PGRST116') {
      console.error('[SupabaseDB] getProfileByEmail:', error.message);
    }
    return data ?? null;
  },

  async updateProfile(userId, updates) {
    const { data, error } = await this.db
      .from('profiles')
      .update(updates)
      .eq('id', userId)
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  },

  async createProfile(profileData) {
    const { data, error } = await this.db
      .from('profiles')
      .insert(profileData)
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  },

  // =============================================
  // ROSTER
  // =============================================

  async getRoster(coachId) {
    const { data, error } = await this.db
      .from('roster')
      .select(`
        id,
        joined_at,
        diver:profiles!roster_diver_id_fkey (
          id, full_name, email, avatar_url, created_at
        )
      `)
      .eq('coach_id', coachId)
      .order('joined_at', { ascending: false });
    if (error) { console.error('[SupabaseDB] getRoster:', error.message); return []; }
    return data ?? [];
  },

  async getDiverCoach(diverId) {
    const { data, error } = await this.db
      .from('roster')
      .select(`
        coach:profiles!roster_coach_id_fkey (
          id, full_name, email, avatar_url
        )
      `)
      .eq('diver_id', diverId)
      .limit(1)
      .maybeSingle();
    if (error) { console.error('[SupabaseDB] getDiverCoach:', error.message); return null; }
    return data?.coach ?? null;
  },

  async addDiverToRoster(coachId, diverId) {
    const { data, error } = await this.db
      .from('roster')
      .insert({ coach_id: coachId, diver_id: diverId })
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  },

  async removeDiverFromRoster(coachId, diverId) {
    const { error } = await this.db
      .from('roster')
      .delete()
      .eq('coach_id', coachId)
      .eq('diver_id', diverId);
    if (error) throw new Error(error.message);
  },

  // =============================================
  // PARENT-DIVER LINKS
  // =============================================

  async getLinkedDivers(parentId) {
    const { data, error } = await this.db
      .from('parent_diver')
      .select(`
        id,
        diver:profiles!parent_diver_diver_id_fkey (
          id, full_name, email, avatar_url
        )
      `)
      .eq('parent_id', parentId);
    if (error) { console.error('[SupabaseDB] getLinkedDivers:', error.message); return []; }
    return data ?? [];
  },

  async linkParentToDiver(parentId, diverId) {
    const { data, error } = await this.db
      .from('parent_diver')
      .insert({ parent_id: parentId, diver_id: diverId })
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  },

  // =============================================
  // SKILL COMPLETIONS
  // =============================================

  async getCompletions(diverId) {
    const { data, error } = await this.db
      .from('skill_completions')
      .select('*')
      .eq('diver_id', diverId)
      .order('self_reported_at', { ascending: false });
    if (error) { console.error('[SupabaseDB] getCompletions:', error.message); return []; }
    return data ?? [];
  },

  // Returns quick-lookup map: skillId → completion row
  async getCompletionMap(diverId) {
    const rows = await this.getCompletions(diverId);
    const map = {};
    rows.forEach(r => { map[r.skill_id] = r; });
    return map;
  },

  async selfReportSkill(diverId, skillId) {
    const { data, error } = await this.db
      .from('skill_completions')
      .upsert(
        {
          diver_id:        diverId,
          skill_id:        skillId,
          self_reported_at: new Date().toISOString(),
        },
        { onConflict: 'diver_id,skill_id' }
      )
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  },

  async confirmSkill(completionId, coachId, notes = '') {
    const { data, error } = await this.db
      .from('skill_completions')
      .update({
        coach_confirmed_at: new Date().toISOString(),
        coach_id:           coachId,
        notes:              notes,
      })
      .eq('id', completionId)
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  },

  async unconfirmSkill(completionId) {
    const { data, error } = await this.db
      .from('skill_completions')
      .update({ coach_confirmed_at: null, coach_id: null })
      .eq('id', completionId)
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  },

  async getRecentCompletions(diverId, limit = 6) {
    const { data, error } = await this.db
      .from('skill_completions')
      .select(`
        *,
        skill:skills (id, skill_name, skill_level)
      `)
      .eq('diver_id', diverId)
      .not('self_reported_at', 'is', null)
      .order('self_reported_at', { ascending: false })
      .limit(limit);
    if (error) return [];
    return data ?? [];
  },

  // All self-reported (unconfirmed) completions across a coach's entire roster,
  // joined with skill name so the UI can display it without a separate lookup.
  async getPendingForCoach(coachId) {
    const roster = await this.getRoster(coachId);
    const diverIds = roster.map(r => r.diver.id);
    if (!diverIds.length) return [];

    const { data, error } = await this.db
      .from('skill_completions')
      .select(`
        *,
        skill:skills (id, skill_name, skill_level),
        diver:profiles!skill_completions_diver_id_fkey (
          id, full_name, avatar_url
        )
      `)
      .in('diver_id', diverIds)
      .not('self_reported_at', 'is', null)
      .is('coach_confirmed_at', null)
      .order('self_reported_at', { ascending: false });
    if (error) { console.error('[SupabaseDB] getPendingForCoach:', error.message); return []; }
    return data ?? [];
  },

  // Completion stats for a diver: { confirmed, selfReported, total }
  async getCompletionStats(diverId) {
    const rows = await this.getCompletions(diverId);
    return {
      confirmed:    rows.filter(r => r.coach_confirmed_at).length,
      selfReported: rows.filter(r => r.self_reported_at && !r.coach_confirmed_at).length,
      total:        rows.length,
    };
  },
};
