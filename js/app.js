// =============================================
// DIVE DRILLS — App Utilities & Navigation
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

    // Define nav links; filter by role.
    // Profile is accessed via the user card in the sidebar footer (desktop)
    // and the initials avatar in the bottom nav (mobile) — no separate nav item.
    const links = [
      { href: 'dashboard.html', icon: '🏠', label: 'Dashboard',     roles: ['coach', 'diver', 'parent'] },
      { href: 'progress.html',  icon: '📊', label: 'Progress',      roles: ['diver'] },
      { href: 'skills.html',    icon: '🎯', label: 'Skills',         roles: ['coach', 'diver', 'parent'] },
      { href: 'roster.html',    icon: '👥', label: 'Roster',        roles: ['coach'] },
      { href: 'testing.html',   icon: '📋', label: 'Testing',       roles: ['coach'] },
    ].filter(l => l.roles.includes(role));

    // Reports — visible to every role, always pinned to the end of the nav.
    const reportsLink = { href: 'stats.html', icon: '📈', label: 'Reports' };

    const isActive = href => currentPage === href ? 'active' : '';

    // ---- Sidebar ----
    const sidebar = document.getElementById('sidebar');
    if (sidebar) {
      sidebar.innerHTML = `
        <div class="sidebar-brand">
          <a href="dashboard.html" class="brand-link">
            <img src="assets/icons/diver-icon.svg" alt="" class="brand-icon">
            <div>
              <span class="brand-name">Dive<span>Drills</span></span>
              <div class="brand-tagline">Skills Tracker</div>
            </div>
          </a>
        </div>
        <nav class="sidebar-nav">
          ${links.map(l => `
            <a href="${l.href}" class="nav-item ${isActive(l.href)}">
              <span class="nav-icon">${l.icon}</span>
              <span>${l.label}</span>
            </a>
          `).join('')}
          <div class="sidebar-nav-divider"></div>
          <a href="${reportsLink.href}" class="nav-item ${isActive(reportsLink.href)}">
            <span class="nav-icon">${reportsLink.icon}</span>
            <span>${reportsLink.label}</span>
          </a>
        </nav>
        <div class="sidebar-footer">
          <a href="profile.html" class="user-info-nav" style="text-decoration:none;display:flex;align-items:center;gap:10px;padding:8px;border-radius:8px;transition:background 0.15s;" onmouseover="this.style.background='var(--surface-2)'" onmouseout="this.style.background=''">
            <div class="avatar-sm">${initials}</div>
            <div class="min-w-0">
              <div class="user-name-nav truncate">${this.escHtml(this.firstName(user))}</div>
              <div class="user-role-nav">${Auth.getRoleLabel(role)}</div>
            </div>
          </a>
          <button class="btn btn-ghost btn-sm w-full" onclick="Auth.logout()">Sign Out</button>
        </div>
      `;
    }

    // ---- Bottom nav (mobile) ----
    // Profile is shown as an initials avatar instead of a generic icon.
    const bottomNav = document.getElementById('bottom-nav');
    if (bottomNav) {
      bottomNav.innerHTML = links.map(l => `
        <a href="${l.href}" class="bottom-nav-item ${isActive(l.href)}">
          <span class="nav-icon">${l.icon}</span>
          <span>${l.label}</span>
        </a>
      `).join('') + `
        <a href="${reportsLink.href}" class="bottom-nav-item bottom-nav-item-reports ${isActive(reportsLink.href)}">
          <span class="nav-icon">${reportsLink.icon}</span>
          <span>${reportsLink.label}</span>
        </a>
        <a href="profile.html" class="bottom-nav-item ${isActive('profile.html')}">
          <span class="nav-icon">
            <span style="display:inline-flex;align-items:center;justify-content:center;width:26px;height:26px;border-radius:50%;background:var(--accent);color:#000;font-size:10px;font-weight:700;line-height:1;">${this.escHtml(initials)}</span>
          </span>
          <span>Profile</span>
        </a>
      `;
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
  // IMAGE LIGHTBOX — full-size view for skill photo thumbnails
  // =============================================
  openImageLightbox(url) {
    if (!url) return;
    let overlay = document.getElementById('image-lightbox');
    if (!overlay) {
      overlay = document.createElement('div');
      overlay.id = 'image-lightbox';
      overlay.className = 'image-lightbox';
      overlay.innerHTML = '<img alt="">';
      overlay.addEventListener('click', () => overlay.classList.remove('visible'));
      document.addEventListener('keydown', e => {
        if (e.key === 'Escape') overlay.classList.remove('visible');
      });
      document.body.appendChild(overlay);
    }
    overlay.querySelector('img').src = url;
    overlay.classList.add('visible');
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
  // STAGE STATUS HELPERS (3-stage skill progression)
  // =============================================
  stageStatus(completion) {
    if (!completion)                  return 'none';
    if (completion.tested_and_passed) return 'certified';
    if (completion.ready_for_test)    return 'ready';
    if (completion.skill_attained)    return 'attained';
    return 'none';
  },

  stageBadgeHtml(completion) {
    const status = this.stageStatus(completion);
    if (status === 'certified') return '<span class="badge badge-accent">✓ Certified</span>';
    if (status === 'ready')     return '<span class="badge badge-pending">Ready for Test</span>';
    if (status === 'attained')  return '<span class="badge" style="background:rgba(59,130,246,.12);color:#3b82f6">Attained</span>';
    return '';
  },

  // =============================================
  // STAR RATINGS
  // Renders a gold/gray star bar sized by percentage fill (via CSS clip),
  // so half-star (and any fractional) ratings render smoothly without
  // relying on a half-star glyph.
  // =============================================

  // Compact read-only stars for skill cards — numeric + stars, no count.
  // Returns '' if there are no ratings yet (cards show nothing in that case).
  starRatingCompactHtml(average, count) {
    if (!count) return '';
    const pct = Math.max(0, Math.min(100, (average / 5) * 100));
    return `
      <span class="star-rating star-rating-sm">
        <span class="star-rating-value">${average.toFixed(1)}</span>
        <span class="star-rating-stars">
          <span class="star-rating-stars-bg">☆☆☆☆☆</span>
          <span class="star-rating-stars-fg" style="width:${pct}%">★★★★★</span>
        </span>
      </span>
    `;
  },

  // Full read-only stars for the skill detail modal — numeric + stars + count.
  starRatingFullHtml(average, count) {
    if (!count) {
      return `
        <span class="star-rating star-rating-lg">
          <span class="star-rating-stars">
            <span class="star-rating-stars-bg">☆☆☆☆☆</span>
          </span>
          <span class="star-rating-count">No ratings yet</span>
        </span>
      `;
    }
    const pct = Math.max(0, Math.min(100, (average / 5) * 100));
    return `
      <span class="star-rating star-rating-lg">
        <span class="star-rating-value">${average.toFixed(1)}</span>
        <span class="star-rating-stars">
          <span class="star-rating-stars-bg">☆☆☆☆☆</span>
          <span class="star-rating-stars-fg" style="width:${pct}%">★★★★★</span>
        </span>
        <span class="star-rating-count">(${count} rating${count !== 1 ? 's' : ''})</span>
      </span>
    `;
  },

  // =============================================
  // NAME FORMATTING — first_name/last_name aware helpers.
  // Fall back to splitting full_name for any records that
  // haven't been backfilled yet.
  // =============================================
  firstName(person) {
    if (!person) return '';
    if (person.first_name) return person.first_name;
    return (person.full_name || '').trim().split(/\s+/)[0] || '';
  },

  // "Last, First" — used in the roster list.
  formatNameLastFirst(person) {
    if (!person) return '';
    const first = person.first_name || '';
    const last  = person.last_name  || '';
    if (first && last) return `${last}, ${first}`;
    if (last || first) return last || first;
    return person.full_name || '';
  },

  // Sort comparator: by skill_order (curriculum order).
  compareSkillOrder(a, b) {
    const aOrder = a?.order ?? Infinity;
    const bOrder = b?.order ?? Infinity;
    return aOrder - bOrder;
  },

  // Sort comparator: by last_name then first_name (falls back to full_name).
  compareNames(a, b) {
    const aLast  = (a?.last_name  || a?.full_name || '').toLowerCase();
    const bLast  = (b?.last_name  || b?.full_name || '').toLowerCase();
    if (aLast !== bLast) return aLast < bLast ? -1 : 1;
    const aFirst = (a?.first_name || '').toLowerCase();
    const bFirst = (b?.first_name || '').toLowerCase();
    if (aFirst !== bFirst) return aFirst < bFirst ? -1 : 1;
    return 0;
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
