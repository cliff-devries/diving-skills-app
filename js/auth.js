// =============================================
// DIVE DRILLS — Authentication
// Handles login, logout, session management,
// and role-based access control.
// =============================================

const Auth = {
  // Populated after a successful init() call
  currentUser:    null,  // profile row from Supabase `profiles` table
  currentSession: null,  // raw Supabase session object

  // =============================================
  // init() — Call at the top of every protected page.
  //   requireAuth: true  → redirect to login if not signed in
  //   requireAuth: false → used on index.html (redirect *away* if already signed in)
  // Returns the user profile object, or null.
  // =============================================
  async init(requireAuth = true) {
    if (!window.supabaseClient) {
      console.error('[Auth] supabaseClient not ready. Call initSupabase() first.');
      return null;
    }

    // Retrieve existing session from local storage / cookie
    const { data: { session }, error } = await window.supabaseClient.auth.getSession();

    if (error) {
      console.error('[Auth] getSession error:', error.message);
    }

    this.currentSession = session;

    // ---- Not logged in ----
    if (!session) {
      if (requireAuth) {
        // Protected page — send to login
        if (!window.location.pathname.endsWith('index.html') &&
            window.location.pathname !== '/') {
          window.location.href = '/index.html';
        }
      }
      return null;
    }

    // ---- Logged in, but on the login page → redirect to dashboard ----
    if (!requireAuth) {
      window.location.href = '/dashboard.html';
      return null;
    }

    // ---- Fetch user profile from `profiles` table ----
    const profile = await SupabaseDB.getProfile(session.user.id);

    if (!profile) {
      // No profile means this auth user signed up via the claiming flow.
      // Send them to claim.html to find and link their existing profile.
      if (!window.location.pathname.endsWith('claim.html')) {
        window.location.href = '/claim.html';
      }
      return null;
    }

    // Pending/rejected coaches never get access to any protected page
    if (profile.role === 'pending_coach') {
      await window.supabaseClient.auth.signOut();
      if (!window.location.pathname.endsWith('index.html') &&
          window.location.pathname !== '/') {
        window.location.href = '/index.html';
      }
      return null;
    }

    // Active profile required — pending/unclaimed divers can't log in yet
    if (profile.status === 'pending') {
      await window.supabaseClient.auth.signOut();
      if (!window.location.pathname.endsWith('claim.html')) {
        window.location.href = '/claim.html';
      }
      return null;
    }

    this.currentUser = profile;

    // Listen for auth state changes (sign-out from another tab, token refresh, etc.)
    window.supabaseClient.auth.onAuthStateChange((event, newSession) => {
      this.currentSession = newSession;
      if (event === 'SIGNED_OUT') {
        this.currentUser = null;
        window.location.href = '/index.html';
      }
    });

    return profile;
  },

  // =============================================
  // login() — Sign in with email + password.
  // Returns the user profile on success.
  // Throws an Error with a human-readable message on failure.
  // =============================================
  async login(email, password) {
    const { data, error } = await window.supabaseClient.auth.signInWithPassword({
      email: email.trim().toLowerCase(),
      password,
    });

    if (error) {
      // Translate Supabase error messages into friendlier copy
      if (error.message.includes('Invalid login credentials')) {
        throw new Error('Incorrect email or password. Please try again.');
      }
      if (error.message.includes('Email not confirmed')) {
        throw new Error('Please confirm your email address before signing in.');
      }
      throw new Error(error.message);
    }

    const profile = await SupabaseDB.getProfile(data.user.id);
    if (!profile) {
      await window.supabaseClient.auth.signOut();
      throw new Error('Account setup is incomplete. Please contact your coach.');
    }

    // Pending coach — awaiting admin approval
    if (profile.role === 'pending_coach' && profile.status === 'pending') {
      await window.supabaseClient.auth.signOut();
      throw new Error('Your coach account is pending approval. Please check back soon or contact your head coach.');
    }

    // Rejected coach
    if (profile.role === 'pending_coach' && profile.status === 'rejected') {
      await window.supabaseClient.auth.signOut();
      throw new Error('Your coach request was not approved. Please contact the head coach for more information.');
    }

    this.currentUser    = profile;
    this.currentSession = data.session;
    return profile;
  },

  // =============================================
  // changePassword() — Re-authenticate with the current
  // password, then update to the new password.
  // Throws an Error with a human-readable message on failure.
  // =============================================
  async changePassword(currentPassword, newPassword) {
    if (!this.currentUser) {
      throw new Error('You must be signed in to change your password.');
    }

    // Verify the current password by re-authenticating
    const { error: signInError } = await window.supabaseClient.auth.signInWithPassword({
      email: this.currentUser.email,
      password: currentPassword,
    });
    if (signInError) {
      throw new Error('Current password is incorrect.');
    }

    const { error } = await window.supabaseClient.auth.updateUser({ password: newPassword });
    if (error) {
      throw new Error(error.message);
    }
  },

  // =============================================
  // logout() — Sign out and return to login page.
  // =============================================
  async logout() {
    try {
      await window.supabaseClient.auth.signOut();
    } catch (err) {
      console.error('[Auth] Sign-out error:', err.message);
    }
    this.currentUser    = null;
    this.currentSession = null;
    window.location.href = '/index.html';
  },

  // =============================================
  // requireRole() — Enforce role-based access.
  // Pass a single role string or an array of allowed roles.
  // Redirects to dashboard if the current user's role isn't allowed.
  // =============================================
  requireRole(roles) {
    const allowed = Array.isArray(roles) ? roles : [roles];
    if (!this.currentUser || !allowed.includes(this.currentUser.role)) {
      window.location.href = '/dashboard.html';
    }
  },

  // ---- Helpers ----

  hasRole(role)   { return this.currentUser?.role === role; },
  isCoach()       { return this.currentUser?.role === 'coach'; },
  isDiver()       { return this.currentUser?.role === 'diver'; },
  isParent()      { return this.currentUser?.role === 'parent'; },

  getInitials(name) {
    if (!name) return '?';
    return name.trim().split(/\s+/).map(n => n[0]).slice(0, 2).join('').toUpperCase();
  },

  getRoleLabel(role) {
    return { coach: 'Coach', diver: 'Diver', parent: 'Parent' }[role] ?? role;
  },
};
