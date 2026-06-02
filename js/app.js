// =============================================
// DIVING SKILLS — App Utilities & Navigation
// Shared helpers used across all pages.
// =============================================

const App = {

  // =============================================
  // NAV — inject sidebar + bottom nav into the DOM.
  // Call after Auth.init() returns a valid user.
  // =============================================
  renderNav(user) {
    if (!user) return;

    const role        = user.role;
    const initials    = Auth.getInitials(user.full_name);
    const currentPage = window.location.pathname.split('/').pop() || 'dashboard.html';

    // Define nav links; filter by role
    const links = [
      { href: 'dashboard.html', icon: '🏠', label: 'Dashboard',     roles: ['coach', 'diver', 'parent'] },
      { href: 'progress.html',  icon: '📊', label: 'Progress',      roles: ['coach', 'diver', 'parent'] },
      { href: 'skills.html',    icon: '🎯', label: 'Skills Library', roles: ['coach', 'diver', 'parent'] },
      { href: 'roster.html',    icon: '👥', label: 'Roster',        roles: ['coach'] },
      { href: 'profile.html',   icon: '👤', label: 'Profile',       roles: ['coach', 'diver', 'parent'] },
    ].filter(l => l.roles.includes(role));

    const isActive = href => currentPage === href ? 'active' : '';

    // ---- Sidebar ----
    const sidebar = document.getElementById('sidebar');
    if (sidebar) {
      sidebar.innerHTML = `
        <div class="sidebar-brand">
          <div class="brand-name">Diving<span>Skills</span></div>
          <div class="brand-tagline">Skills Tracker</div>
        </div>
        <nav class="sidebar-nav">
          ${links.map(l => `
            <a href="${l.href}" class="nav-item ${isActive(l.href)}">
              <span class="nav-icon">${l.icon}</span>
              <span>${l.label}</span>
            </a>
          `).join('')}
        </nav>
        <div class="sidebar-footer">
          <div class="user-info-nav">
            <div class="avatar-sm">${initials}</div>
            <div class="min-w-0">
              <div class="user-name-nav truncate">${this.escHtml(user.full_name)}</div>
              <div class="user-role-nav">${Auth.getRoleLabel(role)}</div>
            </div>
          </div>
          <button class="btn btn-ghost btn-sm w-full" onclick="Auth.logout()">Sign Out</button>
        </div>
      `;
    }

    // ---- Bottom nav (mobile) ----
    const bottomNav = document.getElementById('bottom-nav');
    if (bottomNav) {
      bottomNav.innerHTML = links.map(l => `
        <a href="${l.href}" class="bottom-nav-item ${isActive(l.href)}">
          <span class="nav-icon">${l.icon}</span>
          <span>${l.label}</span>
        </a>
      `).join('');
    }
  },

  // =============================================
  // TOAST — short pop-up confirmation message
  // =============================================
  showToast(message, type = 'success') {
    const existing = document.getElementById('toast');
    if (existing) existing.remove();

    const toast = document.createElement('div');
    toast.id = 'toast';
    Object.assign(toast.style, {
      background: type === 'success' ? 'var(--accent)' : 'var(--danger)',
      color:      type === 'success' ? '#000' : '#fff',
    });
    toast.textContent = message;
    document.body.appendChild(toast);

    setTimeout(() => {
      toast.style.transition = 'opacity 0.3s ease';
      toast.style.opacity    = '0';
      setTimeout(() => toast.remove(), 320);
    }, 3000);
  },

  // =============================================
  // ALERT HELPERS
  // =============================================
  showAlert(id, message, type = 'error') {
    const el = document.getElementById(id);
    if (!el) return;
    el.className = `alert alert-${type} visible`;
    el.textContent = message;
  },
  hideAlert(id) {
    const el = document.getElementById(id);
    if (el) el.className = 'alert';
  },

  // =============================================
  // BUTTON LOADING STATE
  // =============================================
  setBtnLoading(btn, loading) {
    if (loading) {
      btn.disabled             = true;
      btn.dataset.originalText = btn.textContent;
      btn.innerHTML = '<span class="loading-spinner"></span>';
    } else {
      btn.disabled  = false;
      btn.innerHTML = btn.dataset.originalText ?? 'Submit';
    }
  },

  // =============================================
  // MODAL HELPERS
  // =============================================
  openModal(id) {
    const el = document.getElementById(id);
    if (el) el.classList.add('visible');
  },
  closeModal(id) {
    const el = document.getElementById(id);
    if (el) el.classList.remove('visible');
  },

  // =============================================
  // DATE / TIME FORMATTING
  // =============================================
  formatDate(str) {
    if (!str) return '—';
    return new Date(str).toLocaleDateString('en-US', {
      month: 'short', day: 'numeric', year: 'numeric',
    });
  },

  formatRelative(str) {
    if (!str) return '—';
    const diff = Math.floor((Date.now() - new Date(str)) / 1000);
    if (diff < 60)     return 'just now';
    if (diff < 3600)   return `${Math.floor(diff / 60)}m ago`;
    if (diff < 86400)  return `${Math.floor(diff / 3600)}h ago`;
    if (diff < 604800) return `${Math.floor(diff / 86400)}d ago`;
    return this.formatDate(str);
  },

  // =============================================
  // PROGRESS CALCULATION
  // =============================================
  calcProgress(completed, total) {
    if (!total) return 0;
    return Math.round((completed / total) * 100);
  },

  getLevelLabel(level) {
    if (level === 0) return 'Beginner (Level 0)';
    return `Level ${level}`;
  },

  // =============================================
  // COMPLETION STATUS HELPERS
  // =============================================
  completionStatus(completion) {
    if (!completion)                   return 'none';
    if (completion.coach_confirmed_at) return 'confirmed';
    if (completion.self_reported_at)   return 'self-reported';
    return 'none';
  },

  statusBadgeHtml(completion) {
    const status = this.completionStatus(completion);
    if (status === 'confirmed')    return '<span class="badge badge-accent">✓ Confirmed</span>';
    if (status === 'self-reported') return '<span class="badge badge-pending">⏳ Self-Reported</span>';
    return '';
  },

  // =============================================
  // SECURITY — escape HTML to prevent XSS
  // =============================================
  escHtml(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  },

  // =============================================
  // URL PARAMS
  // =============================================
  getParam(name) {
    return new URLSearchParams(window.location.search).get(name);
  },

  // =============================================
  // LOADING OVERLAY
  // =============================================
  showLoading(containerId, message = 'Loading…') {
    const el = document.getElementById(containerId);
    if (el) {
      el.innerHTML = `
        <div class="loading-overlay">
          <div class="loading-spinner loading-spinner-lg"></div>
          <span>${message}</span>
        </div>
      `;
    }
  },

  showError(containerId, message) {
    const el = document.getElementById(containerId);
    if (el) {
      el.innerHTML = `
        <div class="empty-state">
          <div class="empty-state-icon">⚠️</div>
          <p>${this.escHtml(message)}</p>
        </div>
      `;
    }
  },

  showEmpty(containerId, message, icon = '📭') {
    const el = document.getElementById(containerId);
    if (el) {
      el.innerHTML = `
        <div class="empty-state">
          <div class="empty-state-icon">${icon}</div>
          <p>${this.escHtml(message)}</p>
        </div>
      `;
    }
  },
};
