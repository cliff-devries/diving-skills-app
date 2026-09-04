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

  // Any active coach can update all editable fields on a diver's profile.
  async updateDiverProfileByCoach(diverId, { firstName, lastName, nickname, dateOfBirth, currentLevel, diverGroup, assignedCoachName, startDate, parentEmail, parentPhone, aquaGroup }) {
    const { error } = await this.db.rpc('update_diver_profile_by_coach', {
      p_diver_id:            diverId,
      p_first_name:          firstName          !== undefined ? firstName          : null,
      p_last_name:           lastName           !== undefined ? lastName           : null,
      p_nickname:            nickname           !== undefined ? nickname           : null,
      p_date_of_birth:       dateOfBirth        !== undefined ? dateOfBirth        : null,
      p_current_level:       currentLevel       !== undefined ? currentLevel       : null,
      p_diver_group:         diverGroup         !== undefined ? diverGroup         : null,
      p_assigned_coach_name: assignedCoachName  !== undefined ? assignedCoachName  : null,
      p_start_date:          startDate          !== undefined ? startDate          : null,
      p_parent_email:        parentEmail        !== undefined ? parentEmail        : null,
      p_parent_phone:        parentPhone        !== undefined ? parentPhone        : null,
      p_aqua_group:          aquaGroup          !== undefined ? aquaGroup          : null,
    });
    if (error) throw new Error(error.message);
  },

  // Bulk-recalculates aqua_group for all divers from date_of_birth.
  // Super user only. Returns the count of updated rows.
  async updateAllAquaGroups() {
    const { data, error } = await this.db.rpc('update_all_aqua_groups');
    if (error) throw new Error(error.message);
    return data;
  },

  // Updates both roster.coach_id and profiles.assigned_coach_name for a
  // diver in one atomic call, so the "My Divers" dashboard count and the
  // displayed coach name never drift apart.
  async reassignDiverCoach(diverId, newCoachId) {
    const { error } = await this.db.rpc('reassign_diver_coach', {
      p_diver_id:     diverId,
      p_new_coach_id: newCoachId,
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
  // INVITE LINKS (coach-generated parent/family account self-signup)
  // =============================================

  // Coach generates (or regenerates) a parent invite for a diver on their
  // roster. Returns { token, expires_at }.
  async generateInvite(diverId, inviteType) {
    console.log('[SupabaseDB.generateInvite] p_diver_id:', diverId, 'p_invite_type:', inviteType);
    const { data, error } = await this.db.rpc('generate_profile_invite', {
      p_diver_id:    diverId,
      p_invite_type: inviteType,
    });
    if (error) {
      console.error('[SupabaseDB.generateInvite] RPC error:', error);
      throw new Error(error.message);
    }
    return data?.[0] ?? null;
  },

  // Public lookup of an invite token — used by invite.html (no auth required).
  async getInviteInfo(token) {
    const { data, error } = await this.db.rpc('get_invite_info', { p_token: token });
    if (error) throw new Error(error.message);
    return data?.[0] ?? null;
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

  // Emails a parent invite link via the send-invite-email Netlify function
  // (Brevo REST API) — used so coaches don't have to manually copy/paste
  // the link to the parent themselves.
  async emailParentInvite({ parentEmail, diverName, inviteLink, coachName }) {
    const res = await fetch('/.netlify/functions/send-invite-email', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ parentEmail, diverName, inviteLink, coachName }),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok || !body.success) throw new Error(body.error || 'Failed to send invite email.');
    return body;
  },

  // Club-wide (not roster-scoped) list of active divers eligible for a
  // parent invite: has a parent email on file, not already linked to a
  // parent, and not already invited as one. Backs the "Invite All
  // Parents" button on roster.html — see migration v49 for why this has
  // to be a SECURITY DEFINER RPC rather than a plain client-side query.
  async getUninvitedDiversWithParentEmail() {
    const { data, error } = await this.db.rpc('get_uninvited_divers_with_parent_email');
    if (error) throw new Error(error.message);
    return data ?? [];
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
          date_of_birth, diver_group, start_date, assigned_coach_name, aqua_group, parent_email, parent_phone,
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

  // Returns the linked parent profile for a diver (if one exists via parent_diver).
  async getLinkedParent(diverId) {
    const { data, error } = await this.db
      .from('parent_diver')
      .select(`
        parent:profiles!parent_diver_parent_id_fkey (
          id, full_name, email, phone
        )
      `)
      .eq('diver_id', diverId)
      .limit(1)
      .maybeSingle();
    if (error) { console.error('[SupabaseDB] getLinkedParent:', error.message); return null; }
    return data?.parent ?? null;
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

  // Sets diver status to inactive and removes all roster rows.
  async removeDiverByCoach(diverId) {
    console.log('Removing diver ID:', diverId);
    console.log('Type of diverId:', typeof diverId);
    console.log('Current user:', Auth.currentUser);
    const { data, error } = await this.db.rpc('remove_diver_from_roster', { p_diver_id: diverId });
    console.log('RPC result - data:', data, 'error:', JSON.stringify(error));
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

  // Count of divers on a coach's roster who have at least one curriculum
  // level where EVERY testable skill is both Stage 1 (attained) and Stage 2
  // (ready for test) — i.e. a full level ready to be tested.
  async getFullLevelsReadyToTest() {
    const divers = await this.getAllDivers();
    const diverIds = divers.map(d => d.id);
    if (!diverIds.length) return 0;

    const { data: skills, error: skillsError } = await this.db
      .from('skills')
      .select('id, skill_level, is_testable')
      .eq('is_testable', true)
      .is('deleted_at', null);
    if (skillsError) { console.error('[SupabaseDB] getFullLevelsReadyToTest:', skillsError.message); return 0; }

    const levelSkillIds = new Map();
    (skills ?? []).forEach(s => {
      if (s.skill_level === null || s.skill_level === undefined) return;
      if (!levelSkillIds.has(s.skill_level)) levelSkillIds.set(s.skill_level, new Set());
      levelSkillIds.get(s.skill_level).add(s.id);
    });

    const { data: completions, error: completionsError } = await this.db
      .from('skill_completions')
      .select('diver_id, skill_id, skill:skills(is_testable)')
      .in('diver_id', diverIds)
      .eq('skill_attained', true)
      .eq('ready_for_test', true);
    if (completionsError) { console.error('[SupabaseDB] getFullLevelsReadyToTest:', completionsError.message); return 0; }

    const diverReadySkills = new Map();
    (completions ?? []).forEach(c => {
      if (c.skill?.is_testable === false) return;
      if (!diverReadySkills.has(c.diver_id)) diverReadySkills.set(c.diver_id, new Set());
      diverReadySkills.get(c.diver_id).add(c.skill_id);
    });

    let count = 0;
    for (const diverId of diverIds) {
      const ready = diverReadySkills.get(diverId) ?? new Set();
      for (const skillIds of levelSkillIds.values()) {
        if (skillIds.size === 0) continue;
        if ([...skillIds].every(id => ready.has(id))) { count++; break; }
      }
    }
    return count;
  },

  // Total count of skill_completions rows across a coach's roster where
  // ready_for_test = true, for testable (curriculum) skills only.
  async getTotalSkillsReadyToTest() {
    const divers = await this.getAllDivers();
    const diverIds = divers.map(d => d.id);
    if (!diverIds.length) return 0;

    const { data, error } = await this.db
      .from('skill_completions')
      .select('skill:skills(is_testable)')
      .in('diver_id', diverIds)
      .eq('ready_for_test', true);
    if (error) { console.error('[SupabaseDB] getTotalSkillsReadyToTest:', error.message); return 0; }
    return (data ?? []).filter(r => r.skill?.is_testable !== false).length;
  },

  // Count of skill_completions across a coach's roster where skill_attained
  // = true and skill_attained_at falls within the current calendar month,
  // for testable (curriculum) skills only.
  async getSkillsAttainedThisMonth() {
    const divers = await this.getAllDivers();
    const diverIds = divers.map(d => d.id);
    if (!diverIds.length) return 0;

    const now   = new Date();
    const start = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();
    const end   = new Date(now.getFullYear(), now.getMonth() + 1, 1).toISOString();

    const { data, error } = await this.db
      .from('skill_completions')
      .select('skill_attained_at, skill:skills(is_testable)')
      .in('diver_id', diverIds)
      .eq('skill_attained', true)
      .gte('skill_attained_at', start)
      .lt('skill_attained_at', end);
    if (error) { console.error('[SupabaseDB] getSkillsAttainedThisMonth:', error.message); return 0; }
    return (data ?? []).filter(r => r.skill?.is_testable !== false).length;
  },

  // Cumulative all-time count of skill_completions across a coach's roster
  // where skill_attained = true, for testable (curriculum) skills only.
  async getTotalSkillsAttained() {
    const divers = await this.getAllDivers();
    const diverIds = divers.map(d => d.id);
    if (!diverIds.length) return 0;

    const { data, error } = await this.db
      .from('skill_completions')
      .select('skill:skills(is_testable)')
      .in('diver_id', diverIds)
      .eq('skill_attained', true);
    if (error) { console.error('[SupabaseDB] getTotalSkillsAttained:', error.message); return 0; }
    return (data ?? []).filter(r => r.skill?.is_testable !== false).length;
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

  // Stage 1 — Skill Attained. Settable by the diver's coach or linked parent
  // (family account); a legacy diver-owned row also remains self-settable.
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

  // Stage 2 — Ready for Test. Settable by the diver's coach or linked parent
  // (family account). Requires Stage 1 complete.
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

  // =============================================
  // PENDING COACH REQUESTS
  // =============================================

  // Called right after auth.signUp() on coach-signup.html.
  // Requires an active session (email confirmation must be disabled in Supabase).
  // Inserts directly into profiles — allowed by the RLS INSERT policy added in v17.
  async createPendingCoachProfile(firstName, lastName, email, authUserId) {
    const first    = firstName.trim();
    const last     = (lastName || '').trim() || null;
    const fullName = [first, last].filter(Boolean).join(' ');

    const { data, error } = await this.db
      .from('profiles')
      .insert({
        auth_user_id: authUserId,
        first_name:   first,
        last_name:    last,
        full_name:    fullName,
        email:        email.trim().toLowerCase(),
        role:         'pending_coach',
        status:       'pending',
      })
      .select()
      .single();

    if (error) throw new Error(error.message);
    return data;
  },

  // Returns all profiles with role='pending_coach' and status='pending'.
  // Coach-only — enforced inside the SECURITY DEFINER RPC.
  async getPendingCoaches() {
    const { data, error } = await this.db.rpc('get_pending_coaches');
    if (error) { console.error('[SupabaseDB] getPendingCoaches:', error.message); return []; }
    return data ?? [];
  },

  // Sets role='coach' and status='active' for the given profile.
  async approveCoach(profileId) {
    const { error } = await this.db.rpc('approve_coach', { p_profile_id: profileId });
    if (error) throw new Error(error.message);
  },

  // Sets status='rejected' for the given profile (auth account is kept).
  async rejectCoach(profileId) {
    const { error } = await this.db.rpc('reject_coach', { p_profile_id: profileId });
    if (error) throw new Error(error.message);
  },

  // =============================================
  // TESTING SESSIONS
  // =============================================

  // Returns divers on a coach's roster where at least one level has ALL
  // testable skills at Stage 1 (skill_attained) AND Stage 2 (ready_for_test).
  // Result: [{ diver, readyLevels: [0,1,...] }], sorted by last name.
  async getDiversReadyForFullLevelTest(coachId) {
    const roster = await this.getRoster(coachId);
    const diverIds = roster.map(r => r.diver.id);
    if (!diverIds.length) return [];

    const { data: skills, error: skillsError } = await this.db
      .from('skills')
      .select('id, skill_level, is_testable')
      .eq('is_testable', true)
      .is('deleted_at', null);
    if (skillsError) { console.error('[SupabaseDB] getDiversReadyForFullLevelTest:', skillsError.message); return []; }

    const levelSkillIds = new Map();
    (skills ?? []).forEach(s => {
      if (s.skill_level === null || s.skill_level === undefined) return;
      if (!levelSkillIds.has(s.skill_level)) levelSkillIds.set(s.skill_level, new Set());
      levelSkillIds.get(s.skill_level).add(s.id);
    });

    const { data: completions, error: compError } = await this.db
      .from('skill_completions')
      .select('diver_id, skill_id, skill:skills(is_testable, skill_level)')
      .in('diver_id', diverIds)
      .eq('skill_attained', true)
      .eq('ready_for_test', true);
    if (compError) { console.error('[SupabaseDB] getDiversReadyForFullLevelTest:', compError.message); return []; }

    const diverLevelReady = new Map();
    (completions ?? []).forEach(c => {
      if (c.skill?.is_testable === false) return;
      const level = c.skill?.skill_level;
      if (level === null || level === undefined) return;
      if (!diverLevelReady.has(c.diver_id)) diverLevelReady.set(c.diver_id, new Map());
      const levelMap = diverLevelReady.get(c.diver_id);
      if (!levelMap.has(level)) levelMap.set(level, new Set());
      levelMap.get(level).add(c.skill_id);
    });

    const results = [];
    for (const entry of roster) {
      const diver = entry.diver;
      const diverMap = diverLevelReady.get(diver.id);
      if (!diverMap) continue;

      const readyLevels = [];
      for (const [level, skillIds] of levelSkillIds) {
        if (skillIds.size === 0) continue;
        const ready = diverMap.get(level) ?? new Set();
        if ([...skillIds].every(id => ready.has(id))) readyLevels.push(level);
      }
      if (readyLevels.length > 0) {
        results.push({ diver, readyLevels: readyLevels.sort((a, b) => a - b) });
      }
    }
    return results;
  },

  // Returns testable skills for a level along with the diver's completion row
  // (needed for skill_completion_id when inserting test attempts).
  async getTestingSkillsForDiverLevel(diverId, level) {
    const { data: skills, error: skillsErr } = await this.db
      .from('skills')
      .select('id, skill_name, skill_description, skill_type, skill_category, skill_order, requires_harness')
      .eq('skill_level', level)
      .eq('is_testable', true)
      .is('deleted_at', null)
      .order('skill_order', { ascending: true })
      .order('skill_name',  { ascending: true });
    if (skillsErr) throw new Error(skillsErr.message);

    const skillList = skills ?? [];
    if (!skillList.length) return [];

    const { data: completions, error: compErr } = await this.db
      .from('skill_completions')
      .select('id, skill_id, latest_score, latest_test_date, tested_and_passed')
      .eq('diver_id', diverId)
      .in('skill_id', skillList.map(s => s.id));
    if (compErr) throw new Error(compErr.message);

    const compMap = {};
    (completions ?? []).forEach(c => { compMap[c.skill_id] = c; });

    return skillList.map(s => ({
      id:               s.id,
      name:             s.skill_name,
      description:      s.skill_description || '',
      type:             s.skill_type        || '',
      category:         s.skill_category    || '',
      order:            s.skill_order,
      completionId:     compMap[s.id]?.id                || null,
      latestScore:      compMap[s.id]?.latest_score      ?? null,
      latestTestDate:   compMap[s.id]?.latest_test_date  ?? null,
      testedAndPassed:  compMap[s.id]?.tested_and_passed ?? false,
    }));
  },

  // All level_completions rows the current user is allowed to see (RLS
  // scopes this: coaches see every diver's, a diver sees only their own,
  // a parent sees only their linked diver's) — used by the Reports page.
  async getAllLevelCompletionsWithDiverInfo() {
    const { data, error } = await this.db
      .from('level_completions')
      .select(`
        *,
        diver: profiles!level_completions_diver_id_fkey (id, full_name, first_name, last_name, avatar_url),
        coach: profiles!level_completions_coach_id_fkey (id, full_name)
      `)
      .order('completed_at', { ascending: false });
    if (error) { console.error('[SupabaseDB] getAllLevelCompletionsWithDiverInfo:', error.message); return []; }
    return data ?? [];
  },

  // Saves ONE skill's score immediately (called on every score entry
  // during a testing session, poolside-safe — no waiting for Complete
  // Session). Upserts skill_completions (test fields only — never
  // touches skill_attained or ready_for_test) and inserts a
  // skill_test_attempts row. Returns the skill_completions row id so the
  // caller can pass it back in as completionId on the NEXT save for this
  // skill (an UPDATE instead of another INSERT).
  //
  // REQUIRES: supabase-migration-v20.sql must have been run so that
  // skill_attained and ready_for_test are nullable with no default, and
  // the stage-order constraint is dropped.
  async saveSkillScore({ diverId, skillId, coachId, score, testDate, completionId }) {
    const today    = testDate || new Date().toISOString().slice(0, 10);
    const scoreNum = parseFloat(score);
    let finalCompletionId = completionId;

    if (!finalCompletionId) {
      const { data: newComp, error: insErr } = await this.db
        .from('skill_completions')
        .insert({
          diver_id:          diverId,
          skill_id:          skillId,
          tested_and_passed: scoreNum >= 5.0,
          latest_score:      scoreNum,
          latest_test_date:  today,
        })
        .select('id')
        .single();
      if (insErr) throw new Error(`Skill ${skillId} completion insert failed: ${insErr.message}`);
      finalCompletionId = newComp.id;
    } else {
      const { error: updErr } = await this.db
        .from('skill_completions')
        .update({
          tested_and_passed: scoreNum >= 5.0,
          latest_score:      scoreNum,
          latest_test_date:  today,
        })
        .eq('id', finalCompletionId);
      if (updErr) throw new Error(`Skill ${skillId} completion update failed: ${updErr.message}`);
    }

    const { error: attErr } = await this.db
      .from('skill_test_attempts')
      .insert({
        skill_completion_id: finalCompletionId,
        diver_id:            diverId,
        skill_id:            skillId,
        coach_id:             coachId,
        score:                scoreNum,
        test_date:            today,
      });
    if (attErr) throw new Error(`Skill ${skillId} test attempt insert failed: ${attErr.message}`);

    return { completionId: finalCompletionId };
  },

  // Clears a skill's current score (back to un-tested) without touching
  // skill_test_attempts history — used when a coach empties the score
  // input in the progress-page scoring popup and hits Save.
  async clearSkillScore(completionId) {
    const { data, error } = await this.db
      .from('skill_completions')
      .update({ latest_score: null, latest_test_date: null, tested_and_passed: false })
      .eq('id', completionId)
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  },

  // Saves the FINALIZED result of a level test — status/averageScore/
  // designation are computed by the caller (see computeLevelResult() in
  // testing.html) from the complete, authoritative set of every
  // testable skill in the level (fetched fresh via
  // getTestingSkillsForDiverLevel right before this is called), not just
  // whatever was scored in one sitting. A diver only gets a
  // level_completions row once every skill in the level has been tested
  // — status 'incomplete' means nothing is finalized yet, so this is a
  // no-op for that case (there's nothing correct to record: not passed,
  // not failed, just not done). Individual skill scores are already
  // saved via saveSkillScore() as they're entered, so this never touches
  // skill_completions or skill_test_attempts itself.
  async saveLevelResult({ diverId, level, coachId, status, averageScore, designation, notes }) {
    if (status === 'incomplete') return null;

    const lcPayload = {
      diver_id:      diverId,
      level,
      completed_at:  new Date().toISOString(),
      average_score: averageScore != null ? parseFloat(averageScore.toFixed(2)) : null,
      designation:   designation || null,
      passed:        status === 'passed',
      notes:         notes || null,
      coach_id:      coachId,
    };
    const { data, error } = await this.db
      .from('level_completions')
      .upsert(lcPayload, { onConflict: 'diver_id,level' })
      .select();
    if (error) throw new Error('Failed to save level completion: ' + error.message);
    if (!data || data.length === 0) {
      console.warn('[saveLevelResult] level_completions upsert returned no rows — possible RLS block');
    }
    return data;
  },

  // Total count of diver profiles in the club (all coaches' rosters combined).
  async getTotalDiverCount() {
    const { count, error } = await this.db
      .from('profiles')
      .select('id', { count: 'exact', head: true })
      .eq('role', 'diver');
    if (error) { console.error('[SupabaseDB] getTotalDiverCount:', error.message); return 0; }
    return count ?? 0;
  },

  async getTotalCoachCount() {
    const { count, error } = await this.db
      .from('profiles')
      .select('id', { count: 'exact', head: true })
      .eq('role', 'coach')
      .eq('status', 'active');
    console.log('Coach count result:', count, '| error:', error?.message ?? null);
    if (error) { console.error('[SupabaseDB] getTotalCoachCount:', error.message); return 0; }
    return count ?? 0;
  },

  // Active coach profiles for the Coaches list — sorted last then first name.
  async getActiveCoaches() {
    const { data, error } = await this.db
      .from('profiles')
      .select('id, full_name, first_name, last_name, email, status, is_super_user, created_at')
      .eq('role', 'coach')
      .eq('status', 'active')
      .order('last_name', { ascending: true })
      .order('first_name', { ascending: true });
    if (error) { console.error('[SupabaseDB] getActiveCoaches:', error.message); return []; }
    return data ?? [];
  },

  // All diver profiles in the club (excludes rejected), sorted last then first name.
  async getAllDivers() {
    const { data, error } = await this.db
      .from('profiles')
      .select(`
        id, full_name, first_name, last_name, nickname, gender, email, avatar_url, status, current_level, created_at,
        date_of_birth, diver_group, start_date, assigned_coach_name, aqua_group, parent_email, parent_phone,
        invite_token, invite_token_expires_at, invite_type
      `)
      .eq('role', 'diver')
      .neq('status', 'rejected')
      .neq('status', 'inactive')
      .order('last_name', { ascending: true })
      .order('first_name', { ascending: true });
    if (error) { console.error('[SupabaseDB] getAllDivers:', error.message); return []; }
    return data ?? [];
  },

  // Level completion records for a diver, keyed by level number.
  async getLevelCompletions(diverId) {
    const { data, error } = await this.db
      .from('level_completions')
      .select('*')
      .eq('diver_id', diverId)
      .order('level', { ascending: true });
    if (error) { console.error('[SupabaseDB] getLevelCompletions:', error.message); return []; }
    const map = {};
    (data ?? []).forEach(r => { map[r.level] = r; });
    return map;
  },

  // Count distinct divers with skill_completions records for a given skill.
  async getSkillCompletionCount(skillId) {
    const { data, error } = await this.db
      .from('skill_completions')
      .select('diver_id')
      .eq('skill_id', skillId);
    if (error) { console.error('[SupabaseDB] getSkillCompletionCount:', error.message); return 0; }
    const unique = new Set((data ?? []).map(r => r.diver_id));
    return unique.size;
  },

  // Soft-delete a skill by setting deleted_at = NOW(). Does not remove any data.
  async softDeleteSkill(skillId) {
    const { error } = await this.db
      .from('skills')
      .update({ deleted_at: new Date().toISOString() })
      .eq('id', skillId);
    if (error) throw new Error(error.message);
  },

  // =============================================
  // SKILL RATINGS (coach 1.0-5.0 star ratings)
  // =============================================

  // Average rating + count for one skill. Returns { average: number|null, count: number }.
  async getSkillRating(skillId) {
    const { data, error } = await this.db
      .from('skill_ratings')
      .select('rating')
      .eq('skill_id', skillId);
    if (error) { console.error('[SupabaseDB] getSkillRating:', error.message); return { average: null, count: 0 }; }
    const rows = data ?? [];
    if (!rows.length) return { average: null, count: 0 };
    const avg = rows.reduce((sum, r) => sum + Number(r.rating), 0) / rows.length;
    return { average: avg, count: rows.length };
  },

  // This coach's own rating for a skill, or null if they haven't rated it yet.
  async getCoachSkillRating(skillId, coachId) {
    const { data, error } = await this.db
      .from('skill_ratings')
      .select('rating')
      .eq('skill_id', skillId)
      .eq('coach_id', coachId)
      .maybeSingle();
    if (error) { console.error('[SupabaseDB] getCoachSkillRating:', error.message); return null; }
    return data ? Number(data.rating) : null;
  },

  // Upserts a coach's rating for a skill (one row per skill/coach pair).
  async saveSkillRating(skillId, coachId, rating) {
    const { error } = await this.db
      .from('skill_ratings')
      .upsert(
        { skill_id: skillId, coach_id: coachId, rating },
        { onConflict: 'skill_id,coach_id' }
      );
    if (error) throw new Error(error.message);
  },

  // Average rating + count for many skills in one query — used by the
  // skills library list so it doesn't fire one query per skill card.
  // Returns a map: { [skillId]: { average: number, count: number } }.
  async getBulkSkillRatings(skillIds) {
    const map = {};
    if (!skillIds.length) return map;

    const { data, error } = await this.db
      .from('skill_ratings')
      .select('skill_id, rating')
      .in('skill_id', skillIds);
    if (error) { console.error('[SupabaseDB] getBulkSkillRatings:', error.message); return map; }

    const sums   = {};
    const counts = {};
    (data ?? []).forEach(row => {
      sums[row.skill_id]   = (sums[row.skill_id]   || 0) + Number(row.rating);
      counts[row.skill_id] = (counts[row.skill_id] || 0) + 1;
    });
    Object.keys(counts).forEach(id => {
      map[id] = { average: sums[id] / counts[id], count: counts[id] };
    });
    return map;
  },

  // =============================================
  // STORAGE — SKILL MEDIA UPLOADS
  // =============================================

  // Upload a photo file to the skill-photos bucket.
  // Returns the public URL. Coaches only (enforced by storage RLS).
  async uploadSkillPhoto(skillId, file) {
    const path = `skills/${skillId}/photo-${Date.now()}.jpg`;
    const { error } = await this.db.storage
      .from('skill-photos')
      .upload(path, file, { cacheControl: '3600', upsert: false });
    if (error) throw new Error(error.message);
    const { data: { publicUrl } } = this.db.storage
      .from('skill-photos')
      .getPublicUrl(path);
    return publicUrl;
  },

  // Upload a video file to the skill-videos bucket with XHR progress callbacks.
  // onProgress(pct: number) is called as the upload advances (0–100).
  // Returns the public URL. Coaches only (enforced by storage RLS).
  async uploadSkillVideo(skillId, file, onProgress) {
    const path = `skills/${skillId}/video-${Date.now()}.mp4`;
    const { data: { session } } = await this.db.auth.getSession();
    if (!session) throw new Error('Not authenticated');

    const uploadUrl = `${CONFIG.SUPABASE_URL}/storage/v1/object/skill-videos/${path}`;

    await new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();
      xhr.open('POST', uploadUrl);
      xhr.setRequestHeader('Authorization', `Bearer ${session.access_token}`);
      xhr.setRequestHeader('Content-Type', file.type || 'video/mp4');
      xhr.setRequestHeader('x-upsert', 'false');

      xhr.upload.addEventListener('progress', e => {
        if (e.lengthComputable && onProgress) {
          onProgress(Math.round((e.loaded / e.total) * 100));
        }
      });

      xhr.addEventListener('load', () => {
        if (xhr.status >= 200 && xhr.status < 300) {
          resolve();
        } else {
          let msg = `Upload failed (HTTP ${xhr.status})`;
          try { msg = JSON.parse(xhr.responseText).message || msg; } catch {}
          reject(new Error(msg));
        }
      });
      xhr.addEventListener('error', () => reject(new Error('Network error during video upload')));
      xhr.send(file);
    });

    const { data: { publicUrl } } = this.db.storage
      .from('skill-videos')
      .getPublicUrl(path);
    return publicUrl;
  },

  // =============================================
  // STRENGTH & CONDITIONING LEADERBOARD
  // =============================================

  // All personal-best scores, joined with diver name + aqua_group for grouping/display.
  async getLeaderboardScores() {
    const { data, error } = await this.db
      .from('leaderboard_scores')
      .select(`
        id, diver_id, exercise, score, score_type, recorded_by, recorded_at, notes,
        diver:profiles!leaderboard_scores_diver_id_fkey (id, first_name, last_name, full_name, aqua_group, gender)
      `)
      .order('score', { ascending: false });
    if (error) { console.error('[SupabaseDB] getLeaderboardScores:', error.message); return []; }
    return data ?? [];
  },

  // Current personal best for one diver/exercise (null if none recorded yet).
  async getPersonalBest(diverId, exercise) {
    const { data, error } = await this.db
      .from('leaderboard_scores')
      .select('score')
      .eq('diver_id', diverId)
      .eq('exercise', exercise)
      .maybeSingle();
    if (error) { console.error('[SupabaseDB] getPersonalBest:', error.message); return null; }
    return data?.score ?? null;
  },

  // Upserts a diver's personal best for an exercise (one row per diver/exercise).
  async recordLeaderboardScore(diverId, exercise, score, scoreType, coachId, notes, testDate) {
    const { data, error } = await this.db
      .from('leaderboard_scores')
      .upsert({
        diver_id:    diverId,
        exercise,
        score,
        score_type:  scoreType,
        recorded_by: coachId,
        recorded_at: testDate ? new Date(testDate + 'T00:00:00').toISOString() : new Date().toISOString(),
        notes:       notes || null,
      }, { onConflict: 'diver_id,exercise' })
      .select()
      .single();
    if (error) throw new Error(error.message);
    return data;
  },

  async deleteLeaderboardScore(scoreId) {
    const { error } = await this.db
      .from('leaderboard_scores')
      .delete()
      .eq('id', scoreId);
    if (error) throw new Error(error.message);
  },
};
