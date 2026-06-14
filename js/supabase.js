// =============================================
// DIVE DRILLS — Supabase Database Functions
// All database reads/writes go through this module.
// Uses the global `window.supabaseClient` set by config.js.
// =============================================

const SupabaseDB = {

  get db() { return window.supabaseClient; },

  // =============================================
  // PROFILES
  // =============================================

  // Look up a profile by the Supabase auth user UUID (auth_user_id column).
  // Returns null for unclaimed profiles (they have no auth account).
  async getProfile(authUserId) {
    const { data, error } = await this.db
      .from('profiles')
      .select('*')
      .eq('auth_user_id', authUserId)
      .single();
    if (error && error.code !== 'PGRST116') {
      console.error('[SupabaseDB] getProfile:', error.message);
    }
    return data ?? null;
  },

  async getProfileById(profileId) {
    const { data, error } = await this.db
      .from('profiles')
      .select('*')
      .eq('id', profileId)
      .single();
    if (error && error.code !== 'PGRST116') {
      console.error('[SupabaseDB] getProfileById:', error.message);
    }
    return data ?? null;
  },

  async getProfileByEmail(email) {
    const { data, error } = await this.db
      .from('profiles')
      .select('id, full_name, email, role, avatar_url, status')
      .eq('email', email.trim().toLowerCase())
      .single();
    if (error && error.code !== 'PGRST116') {
      console.error('[SupabaseDB] getProfileByEmail:', error.message);
    }
    return data ?? null;
  },

  async updateProfile(profileId, updates) {
    const { data, error } = await this.db
      .from('profiles')
      .update(updates)
      .eq('id', profileId)
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  },

  // =============================================
  // UNCLAIMED DIVERS (Phase 1 — coach creates)
  // Uses the create_unclaimed_diver RPC which atomically
  // creates the profile and adds it to the coach's roster.
  // =============================================

  async createUnclaimedDiver({ firstName, lastName, email, dateOfBirth, currentLevel, phone, parentGuardian, notes, gender }) {
    const { data, error } = await this.db.rpc('create_unclaimed_diver', {
      p_first_name:      firstName,
      p_last_name:       lastName       || null,
      p_email:           email          || null,
      p_date_of_birth:   dateOfBirth    || null,
      p_current_level:   currentLevel   !== '' ? Number(currentLevel) : null,
      p_phone:           phone          || null,
      p_parent_guardian: parentGuardian || null,
      p_notes:           notes          || null,
      p_gender:          gender         || null,
    });
    if (error) throw new Error(error.message);
    return data; // returns new profile UUID
  },

  // Coach edits the gender of a diver on their roster (covers active,
  // claimed profiles which the coach can't update directly via RLS).
  async updateDiverGender(diverId, gender) {
    const { error } = await this.db.rpc('update_diver_gender', {
      p_diver_id: diverId,
      p_gender:   gender || null,
    });
    if (error) throw new Error(error.message);
  },

  // Search unclaimed/pending profiles by diver name (and optionally coach name).
  // Used on the claim.html page for divers to find themselves.
  async searchUnclaimedProfiles(diverName, coachName) {
    let query = this.db
      .from('profiles')
      .select(`
        id, full_name, current_level, status,
        coach:profiles!profiles_created_by_coach_id_fkey (
          id, full_name
        )
      `)
      .in('status', ['unclaimed', 'pending'])
      .ilike('full_name', `%${diverName.trim()}%`);

    if (coachName && coachName.trim()) {
      // Post-filter client-side after fetching — avoids complex nested filter
    }

    const { data, error } = await query.limit(20);
    if (error) throw new Error(error.message);

    let results = data ?? [];
    if (coachName && coachName.trim()) {
      const q = coachName.trim().toLowerCase();
      results = results.filter(r => r.coach?.full_name?.toLowerCase().includes(q));
    }
    return results;
  },

  // =============================================
  // PROFILE CLAIMS (Phase 2 — diver claims)
  // =============================================

  // Diver submits a claim linking their auth account to an unclaimed profile.
  async createClaim(profileId, authUserId) {
    // First mark profile as pending
    const { error: updateErr } = await this.db
      .from('profiles')
      .update({ status: 'pending' })
      .eq('id', profileId);
    if (updateErr) throw new Error(updateErr.message);

    const { data, error } = await this.db
      .from('profile_claims')
      .insert({ profile_id: profileId, auth_user_id: authUserId })
      .select()
      .single();
    if (error) {
      // Roll back status if claim insert fails
      await this.db.from('profiles').update({ status: 'unclaimed' }).eq('id', profileId);
      throw new Error(error.message);
    }
    return data;
  },

  // Check if the current auth user already has a pending claim
  async getMyPendingClaim(authUserId) {
    const { data, error } = await this.db
      .from('profile_claims')
      .select(`
        id,
        created_at,
        profile:profiles (
          id, full_name, current_level,
          coach:profiles!profiles_created_by_coach_id_fkey (full_name)
        )
      `)
      .eq('auth_user_id', authUserId)
      .maybeSingle();
    if (error) { console.error('[SupabaseDB] getMyPendingClaim:', error.message); return null; }
    return data ?? null;
  },

  // Coach: get all pending claims for divers they created
  async getPendingClaimsForCoach(coachId) {
    const { data, error } = await this.db
      .from('profile_claims')
      .select(`
        id,
        auth_user_id,
        created_at,
        profile:profiles!profile_claims_profile_id_fkey (
          id, full_name, current_level, date_of_birth
        )
      `)
      .order('created_at', { ascending: true });

    if (error) { console.error('[SupabaseDB] getPendingClaimsForCoach:', error.message); return []; }

    // Filter to only claims for profiles this coach created
    // (RLS already limits to coach's profiles, but coachId param for extra safety)
    return data ?? [];
  },

  // Coach approves a claim via RPC (SECURITY DEFINER bypasses RLS for the update)
  async approveClaim(claimId) {
    const { error } = await this.db.rpc('approve_profile_claim', { p_claim_id: claimId });
    if (error) throw new Error(error.message);
  },

  // Coach rejects a claim via RPC
  async rejectClaim(claimId) {
    const { error } = await this.db.rpc('reject_profile_claim', { p_claim_id: claimId });
    if (error) throw new Error(error.message);
  },

  // =============================================
  // INVITE LINKS (coach-generated diver/parent self-signup)
  // =============================================

  // Coach generates (or regenerates) an invite for a diver on their roster.
  // Returns { token, expires_at }.
  async generateInvite(diverId, inviteType) {
    const { data, error } = await this.db.rpc('generate_profile_invite', {
      p_diver_id:    diverId,
      p_invite_type: inviteType,
    });
    if (error) throw new Error(error.message);
    return data?.[0] ?? null;
  },

  // Public lookup of an invite token — used by invite.html (no auth required).
  async getInviteInfo(token) {
    const { data, error } = await this.db.rpc('get_invite_info', { p_token: token });
    if (error) throw new Error(error.message);
    return data?.[0] ?? null;
  },

  // Diver completes signup: links their new auth account to the unclaimed
  // profile that owns this token, and consumes the token.
  async completeDiverInvite(token) {
    const { error } = await this.db.rpc('complete_diver_invite', { p_token: token });
    if (error) throw new Error(error.message);
  },

  // Parent completes signup: links their (newly-created) parent profile to
  // the diver named in this token via parent_diver, and consumes the token.
  async completeParentInvite(token, relationship) {
    const { error } = await this.db.rpc('complete_parent_invite', {
      p_token:        token,
      p_relationship: relationship,
    });
    if (error) throw new Error(error.message);
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
          id, full_name, first_name, last_name, gender, email, avatar_url, status, current_level, created_at,
          invite_token, invite_token_expires_at, invite_type
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
          id, full_name, first_name, last_name, email, avatar_url
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
      .select('*, skill:skills(is_testable)')
      .eq('diver_id', diverId);
    if (error) { console.error('[SupabaseDB] getCompletions:', error.message); return []; }
    return data ?? [];
  },

  async getCompletionMap(diverId) {
    const rows = await this.getCompletions(diverId);
    const map = {};
    rows.forEach(r => { map[r.skill_id] = r; });
    return map;
  },

  // Stage-1/2/3 counts for a diver, used on the dashboard and profile page.
  // Only counts testable (curriculum) skills — supplemental skills are excluded.
  async getCompletionStats(diverId) {
    const rows = (await this.getCompletions(diverId)).filter(r => r.skill?.is_testable !== false);
    return {
      attained:     rows.filter(r => r.skill_attained).length,
      readyForTest: rows.filter(r => r.ready_for_test && !r.tested_and_passed).length,
      certified:    rows.filter(r => r.tested_and_passed).length,
      total:        rows.length,
    };
  },

  // Stage-1/2/3 counts for every diver in diverIds, keyed by diver id.
  // Used by the roster page to summarize each diver's progress in one query.
  async getRosterCompletionStats(diverIds) {
    const stats = {};
    if (!diverIds.length) return stats;

    const { data, error } = await this.db
      .from('skill_completions')
      .select('diver_id, skill_attained, ready_for_test, tested_and_passed')
      .in('diver_id', diverIds);
    if (error) { console.error('[SupabaseDB] getRosterCompletionStats:', error.message); return stats; }

    for (const row of data ?? []) {
      const s = stats[row.diver_id] ?? (stats[row.diver_id] = { attained: 0, readyForTest: 0, certified: 0 });
      if (row.skill_attained) s.attained++;
      if (row.ready_for_test && !row.tested_and_passed) s.readyForTest++;
      if (row.tested_and_passed) s.certified++;
    }
    return stats;
  },

  // Recent test attempts for a diver, used as "Recent Activity" on the dashboard.
  async getRecentTestAttempts(diverId, limit = 6) {
    const { data, error } = await this.db
      .from('skill_test_attempts')
      .select(`*, skill:skills (id, skill_name, skill_level)`)
      .eq('diver_id', diverId)
      .order('created_at', { ascending: false })
      .limit(limit);
    if (error) { console.error('[SupabaseDB] getRecentTestAttempts:', error.message); return []; }
    return data ?? [];
  },

  // Skills that are ready for testing across a coach's roster (Stage 2 done,
  // Stage 3 not yet). Used for the coach dashboard/roster "needs testing" queue.
  // Only includes testable (curriculum) skills — supplemental skills are excluded.
  async getReadyForTestForCoach(coachId) {
    const roster = await this.getRoster(coachId);
    const diverIds = roster.map(r => r.diver.id);
    if (!diverIds.length) return [];

    const { data, error } = await this.db
      .from('skill_completions')
      .select(`
        *,
        skill:skills (id, skill_name, skill_level, is_testable),
        diver:profiles!skill_completions_diver_id_fkey (
          id, full_name, first_name, last_name, avatar_url
        )
      `)
      .in('diver_id', diverIds)
      .eq('ready_for_test', true)
      .eq('tested_and_passed', false)
      .order('ready_for_test_at', { ascending: true });
    if (error) { console.error('[SupabaseDB] getReadyForTestForCoach:', error.message); return []; }
    return (data ?? []).filter(r => r.skill?.is_testable !== false);
  },

  // =============================================
  // THREE-STAGE SKILL PROGRESSION
  // =============================================

  // Internal helper: upsert a skill_completions row by (diver_id, skill_id).
  async _upsertCompletion(diverId, skillId, updates) {
    const { data, error } = await this.db
      .from('skill_completions')
      .upsert(
        { diver_id: diverId, skill_id: skillId, ...updates },
        { onConflict: 'diver_id,skill_id' }
      )
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  },

  // Stage 1 — Skill Attained. Settable by the diver (own row) or their coach.
  async setSkillAttained(diverId, skillId, userId, attained) {
    const updates = attained
      ? {
          skill_attained:    true,
          skill_attained_at: new Date().toISOString(),
          skill_attained_by: userId,
        }
      : {
          skill_attained:    false,
          skill_attained_at: null,
          skill_attained_by: null,
          // Cascade: a skill can't be ready for test if it's no longer attained.
          ready_for_test:    false,
          ready_for_test_at: null,
          ready_for_test_by: null,
        };
    return this._upsertCompletion(diverId, skillId, updates);
  },

  // Stage 2 — Ready for Test. Coach only. Requires Stage 1 complete.
  async setReadyForTest(diverId, skillId, coachId, ready) {
    const updates = ready
      ? {
          ready_for_test:    true,
          ready_for_test_at: new Date().toISOString(),
          ready_for_test_by: coachId,
        }
      : {
          ready_for_test:    false,
          ready_for_test_at: null,
          ready_for_test_by: null,
          // Cascade: a skill can't be tested and passed if it's no longer ready for test.
          tested_and_passed: false,
        };
    return this._upsertCompletion(diverId, skillId, updates);
  },

  // Stage 3 — Tested and Passed. Coach only. Requires Stages 1 & 2 complete.
  // Inserts a new test attempt record (history is never overwritten) and
  // marks the skill_completions row as tested_and_passed.
  async recordTestAttempt({ skillCompletionId, diverId, skillId, coachId, score, testDate, notes }) {
    const payload = {
      skill_completion_id: skillCompletionId,
      diver_id:            diverId,
      skill_id:            skillId,
      coach_id:            coachId,
      score:               score,
      test_date:           testDate,
      notes:               notes || '',
    };
    const { data: attempt, error: attemptError } = await this.db
      .from('skill_test_attempts')
      .insert(payload)
      .select()
      .single();
    if (attemptError) {
      throw new Error(attemptError.message);
    }

    const { data: completion, error: completionError } = await this.db
      .from('skill_completions')
      .update({ tested_and_passed: true })
      .eq('id', skillCompletionId)
      .select()
      .single();
    if (completionError) throw new Error(completionError.message);

    return { attempt, completion };
  },

  // Full attempt history for one skill (most recent first).
  async getTestAttempts(skillCompletionId) {
    const { data, error } = await this.db
      .from('skill_test_attempts')
      .select('*')
      .eq('skill_completion_id', skillCompletionId)
      .order('test_date', { ascending: false })
      .order('created_at', { ascending: false });
    if (error) { console.error('[SupabaseDB] getTestAttempts:', error.message); return []; }
    return data ?? [];
  },

  // All attempts for a diver, used to show "most recent attempt" per skill
  // on the progress page without an extra round-trip per skill.
  async getAllTestAttempts(diverId) {
    const { data, error } = await this.db
      .from('skill_test_attempts')
      .select('*')
      .eq('diver_id', diverId)
      .order('test_date', { ascending: false })
      .order('created_at', { ascending: false });
    if (error) { console.error('[SupabaseDB] getAllTestAttempts:', error.message); return []; }
    return data ?? [];
  },

  // =============================================
  // CLUB SETTINGS (club-wide manual values, e.g. team rankings)
  // =============================================

  // Fetch a map of setting_key -> setting_value for the given keys.
  async getClubSettings(keys) {
    const { data, error } = await this.db
      .from('club_settings')
      .select('setting_key, setting_value')
      .in('setting_key', keys);
    if (error) { console.error('[SupabaseDB] getClubSettings:', error.message); return {}; }
    const map = {};
    (data ?? []).forEach(row => { map[row.setting_key] = row.setting_value; });
    return map;
  },

  // Coach-only (enforced by RLS) — create or update a club setting.
  async setClubSetting(key, value, userId) {
    const { error } = await this.db
      .from('club_settings')
      .upsert(
        { setting_key: key, setting_value: value, updated_by: userId, updated_at: new Date().toISOString() },
        { onConflict: 'setting_key' }
      );
    if (error) throw new Error(error.message);
  },
};
