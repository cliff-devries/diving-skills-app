// =============================================
// DIVE DRILLS — Test Report PDF generation
// Builds a light/white-theme PDF test report for one diver/level from the
// current database state (skills, skill_completions, level_completions).
// No storage — always generated fresh, so a retest is reflected immediately.
// Requires jsPDF + html2canvas (loaded via CDN) on any page that uses this.
//
// PAGE-BREAK STRATEGY: each skill-type section (and the header block, and
// the summary+comments block) is rasterized as its own separate html2canvas
// capture, then placed onto the PDF with a running Y-position tracker — if a
// block doesn't fit in the remaining space on the current page, a new page
// starts before it's placed. Because a section header and its skill rows
// are baked into the SAME image, a section can never be split mid-list or
// left orphaned from its header.
//   - CSS page-break-* properties were not used: html2canvas does not
//     implement the CSS Paged Media spec at all — it rasterizes a flat DOM
//     subtree into a single canvas with no concept of "pages", so those
//     properties are silently ignored. They only work with real print
//     engines (browser window.print(), wkhtmltopdf, Puppeteer's page.pdf()).
//   - A per-row (rather than per-section) height/Y-tracker was not used
//     either: it would need one html2canvas call per skill row (47+ per
//     report) instead of one per section (at most 16), for no benefit here
//     — most levels' skill types hold a handful of skills each, never more
//     than fits on one page, so section-level atomicity already guarantees
//     no split/orphaned rows at a fraction of the cost.
//   - EXCEPTION — large sections: a section with more than
//     SECTION_CHUNK_SIZE rows (e.g. a level with an unusually large skill
//     count in one type) is split into multiple capture blocks instead of
//     one giant one: [header + first chunk], then subsequent row-chunks,
//     then the average footer. A tall single html2canvas capture is more
//     prone to stalling on mobile Safari, so this trades a small chance of
//     a page break landing between two row-chunks (rare, and each chunk is
//     small enough to never itself split) for much smaller, more reliable
//     captures. Small/typical sections are unaffected — still one atomic
//     block as described above.
// =============================================

const Reports = {

  // iOS Safari + html2canvas is occasionally unreliable (can stall
  // indefinitely rather than throw). This caps how long generation is
  // allowed to hang before we give up and, on iOS, fall back to
  // window.print() instead of leaving the UI spinning forever.
  PDF_TIMEOUT_MS: 30000,

  // A level with more total skills than this gets extra mobile memory
  // management (lower capture scale, longer inter-capture delay) — sized
  // off the actual level being rendered, not any specific level number,
  // since whichever level ends up with the most skills is the one at risk.
  LARGE_LEVEL_SKILL_THRESHOLD: 50,

  // Sections taller than this many rows are split into multiple smaller
  // html2canvas captures instead of one — see the page-break strategy note
  // above.
  SECTION_CHUNK_SIZE: 15,

  SECTION_ORDER: [
    'Basics', 'Conditioning', 'Flexibility', 'Trampoline', 'Trampoline in Belt',
    'Dryboard', 'Dryboard in Belt', 'Dry Platform', '1m Platform', '1m Platform in Belt',
    '1m Springboard', '3m Springboard', 'Platform', 'Pool', 'Games', 'Bonus',
  ],

  COLORS: {
    accent:        '#00c9a7',
    textPrimary:   '#1a1a1a',
    textSecondary: '#666666',
    rowAlt:        '#f9f9f9',
    border:        '#e0e0e0',
    gold:          '#f5c518',
    silver:        '#c0c0c0',
    bronze:        '#cd7f32',
    passed:        '#00c9a7',
    failed:        '#e05252',
    incomplete:    '#f5a623',
  },

  // =============================================
  // DATA
  // =============================================

  async gatherReportData(diverId, level) {
    const [diver, skills, levelCompMap] = await Promise.all([
      SupabaseDB.getProfileById(diverId),
      SupabaseDB.getTestingSkillsForDiverLevel(diverId, level),
      SupabaseDB.getLevelCompletions(diverId),
    ]);
    const levelComp = levelCompMap[level] || null;
    const coach = levelComp?.coach_id ? await SupabaseDB.getProfileById(levelComp.coach_id) : null;
    return { diver, skills, levelComp, coach, level };
  },

  // A level counts as reportable once at least one skill has a score.
  hasTestedSkills(skills) {
    return skills.some(s => s.latestScore != null);
  },

  // =============================================
  // PASS / FAIL / INCOMPLETE — thin wrapper around App.computeLevelResult()
  // (js/app.js), the single shared implementation also used by
  // testing.html's Complete Session and progress.html's level header
  // badge, so all three always agree. Computed fresh from the skills
  // list every time (not from the stored level_completions.designation/
  // passed), so a single retest is reflected immediately without needing
  // that row recomputed. This wrapper just adapts the shared
  // status/averageScore/designation shape to the field names and PDF
  // presentation (label/bg/color) the rest of this file already expects.
  // =============================================

  computeResult(skills) {
    const c    = this.COLORS;
    const base = App.computeLevelResult(skills);
    const tested = skills.filter(s => s.latestScore != null);

    if (base.status === 'incomplete') {
      return { status: 'incomplete', label: 'INCOMPLETE', bg: c.incomplete, color: '#ffffff', tested, failed: base.failing, avg: base.averageScore };
    }
    if (base.status === 'failed') {
      return { status: 'failed', label: 'FAILED', bg: c.failed, color: '#ffffff', tested, failed: base.failing, avg: base.averageScore };
    }
    if (base.designation === 'gold')   return { status: 'gold',   label: '🥇 Gold',   bg: c.gold,   color: '#1a1a1a', tested, failed: base.failing, avg: base.averageScore };
    if (base.designation === 'silver') return { status: 'silver', label: '🥈 Silver', bg: c.silver, color: '#1a1a1a', tested, failed: base.failing, avg: base.averageScore };
    if (base.designation === 'bronze') return { status: 'bronze', label: '🥉 Bronze', bg: c.bronze, color: '#ffffff', tested, failed: base.failing, avg: base.averageScore };
    return { status: 'passed', label: '✅ Passed', bg: c.passed, color: '#ffffff', tested, failed: base.failing, avg: base.averageScore };
  },

  // =============================================
  // HTML FRAGMENTS (each one is rasterized as its own atomic block — see
  // the page-break strategy note at the top of this file)
  // =============================================

  _calcAge(dob) {
    if (!dob) return null;
    const birth = new Date(dob + 'T00:00:00');
    const today = new Date();
    let age = today.getFullYear() - birth.getFullYear();
    const m = today.getMonth() - birth.getMonth();
    if (m < 0 || (m === 0 && today.getDate() < birth.getDate())) age--;
    return age;
  },

  _formatDate(dateStr) {
    if (!dateStr) return '—';
    const [y, m, d] = dateStr.split('-').map(Number);
    return new Date(y, m - 1, d).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
  },

  _groupByType(skills) {
    const byType = {};
    skills.forEach(s => { (byType[s.type || 'General'] ??= []).push(s); });
    const ordered = [
      ...this.SECTION_ORDER.filter(t => byType[t]),
      ...Object.keys(byType).filter(t => !this.SECTION_ORDER.includes(t)).sort(),
    ];
    return ordered.map(type => ({
      type,
      skills: byType[type].slice().sort((a, b) => (a.order ?? Infinity) - (b.order ?? Infinity)),
    }));
  },

  _headerBlockHtml(data, result) {
    const c = this.COLORS;
    const { diver, coach, level } = data;
    const age  = this._calcAge(diver.date_of_birth);
    const dob  = this._formatDate(diver.date_of_birth);
    const name = App.formatNameLastFirst(diver) || diver.full_name || '';
    const initials = Auth.getInitials(diver.full_name || '');

    const testDates = result.tested.map(s => s.latestTestDate).filter(Boolean).sort();
    const mostRecentTestDate = testDates.length ? testDates[testDates.length - 1] : null;

    return `
      <div style="font-family:Helvetica,Arial,sans-serif;color:${c.textPrimary};background:#ffffff">
        <div style="display:flex;align-items:flex-start;justify-content:space-between">
          <div style="font-size:15px;font-weight:700;color:${c.textPrimary}">Upstate Diving</div>
          <img src="assets/icons/diver-icon.svg" style="width:36px;height:36px" alt="">
        </div>
        <div style="font-size:24px;font-weight:800;letter-spacing:0.02em;margin-top:6px">DIVE DRILLS TEST REPORT</div>
        <div style="height:3px;background:${c.accent};margin-top:10px;margin-bottom:18px"></div>

        <div style="display:flex;align-items:center;gap:14px;margin-bottom:16px">
          <div style="width:56px;height:56px;border-radius:50%;background:${c.accent};color:#ffffff;font-size:20px;font-weight:700;display:flex;align-items:center;justify-content:center;flex-shrink:0">${App.escHtml(initials)}</div>
          <div style="flex:1">
            <div style="font-size:19px;font-weight:700">${App.escHtml(name)}</div>
            <div style="font-size:11px;color:${c.textSecondary};margin-top:2px">
              ${age !== null ? `Age ${age} &middot; ` : ''}DOB: ${dob}
            </div>
          </div>
          <div style="background:${result.bg};color:${result.color};font-weight:700;font-size:12px;padding:6px 14px;border-radius:14px;white-space:nowrap">
            ${result.label}
          </div>
        </div>

        <table style="width:100%;border-collapse:collapse;margin-bottom:6px;font-size:11px">
          <tr>
            <td style="padding:3px 0;color:${c.textSecondary};width:120px">Level Tested</td>
            <td style="padding:3px 0;font-weight:600">${App.escHtml(App.getLevelLabel(level))}</td>
            <td style="padding:3px 0;color:${c.textSecondary};width:120px">Date of Test</td>
            <td style="padding:3px 0;font-weight:600">${this._formatDate(mostRecentTestDate)}</td>
          </tr>
          <tr>
            <td style="padding:3px 0;color:${c.textSecondary}">Coach</td>
            <td style="padding:3px 0;font-weight:600" colspan="3">${coach ? App.escHtml(coach.full_name) : '—'}</td>
          </tr>
        </table>
        <div style="height:1px;background:${c.border};margin-top:12px"></div>
      </div>`;
  },

  _skillRowHtml(skill, idx) {
    const c = this.COLORS;
    const bg = idx % 2 === 0 ? '#ffffff' : c.rowAlt;
    const tested  = skill.latestScore != null;
    const failing = tested && Number(skill.latestScore) < 5.0;
    const scoreText = tested ? Number(skill.latestScore).toFixed(1) : 'Not tested';
    // Unscored: small muted italic so it reads clearly as "nothing
    // recorded yet", not just a blank/dash easy to skim past. Failing
    // (tested but < 5.0): bold red, so it's obvious at a glance which
    // specific rows are why the level didn't pass.
    const scoreStyle = tested
      ? `font-size:11px;font-weight:${failing ? '700' : '400'};color:${failing ? c.failed : c.textPrimary}`
      : `font-size:9.5px;font-style:italic;color:${c.textSecondary}`;
    const icon = !tested ? '' : (skill.latestScore >= 5.0 ? '✅' : '❌');
    return `
      <tr style="background:${bg}">
        <td style="padding:6px 10px;font-size:11px;color:${c.textPrimary};border-bottom:1px solid ${c.border}">${App.escHtml(skill.name)}</td>
        <td style="padding:6px 10px;border-bottom:1px solid ${c.border};text-align:center;width:60px;${scoreStyle}">${scoreText}</td>
        <td style="padding:6px 10px;font-size:13px;border-bottom:1px solid ${c.border};text-align:center;width:40px">${icon}</td>
      </tr>`;
  },

  _sectionHeaderHtml(group) {
    const c = this.COLORS;
    return `
      <div style="font-family:Helvetica,Arial,sans-serif;background:#ffffff">
        <div style="background:${c.accent};color:#ffffff;font-weight:700;font-size:12px;padding:6px 10px;letter-spacing:0.03em;text-transform:uppercase">
          ${App.escHtml(group.type)}
        </div>
      </div>`;
  },

  // startIdx keeps zebra striping continuous across chunks of the same
  // section, as if the rows had never been split.
  _sectionRowsHtml(skills, startIdx) {
    return `
      <div style="font-family:Helvetica,Arial,sans-serif;background:#ffffff">
        <table style="width:100%;border-collapse:collapse">
          <tbody>${skills.map((s, i) => this._skillRowHtml(s, startIdx + i)).join('')}</tbody>
        </table>
      </div>`;
  },

  // Section average only counts tested skills — untested ('—') skills don't
  // pull it down, and a section with nothing tested yet shows '—'.
  _sectionFooterHtml(group) {
    const c = this.COLORS;
    const tested = group.skills.filter(s => s.latestScore != null);
    const avg = tested.length
      ? (tested.reduce((sum, s) => sum + Number(s.latestScore), 0) / tested.length).toFixed(1)
      : null;
    return `
      <div style="font-family:Helvetica,Arial,sans-serif;background:#ffffff">
        <div style="text-align:right;font-size:10.5px;color:${c.textSecondary};padding:4px 10px;font-style:italic">
          Section Average: ${avg !== null ? avg : '—'}
        </div>
      </div>`;
  },

  _sectionBlockHtml(group) {
    return `${this._sectionHeaderHtml(group)}${this._sectionRowsHtml(group.skills, 0)}${this._sectionFooterHtml(group)}`;
  },

  // Returns an array of { html, label, skillCount } capture blocks for one
  // section. Sections at or under SECTION_CHUNK_SIZE stay a single atomic
  // block (unchanged behavior); larger ones split into [header + first
  // chunk], then further row-chunks, then the average footer.
  _buildSectionBlocks(group) {
    const chunkSize = this.SECTION_CHUNK_SIZE;
    if (group.skills.length <= chunkSize) {
      return [{ html: this._sectionBlockHtml(group), label: group.type, skillCount: group.skills.length }];
    }

    const blocks = [];
    const firstChunk = group.skills.slice(0, chunkSize);
    blocks.push({
      html: `${this._sectionHeaderHtml(group)}${this._sectionRowsHtml(firstChunk, 0)}`,
      label: `${group.type} (rows 1-${firstChunk.length})`,
      skillCount: firstChunk.length,
    });
    for (let i = chunkSize; i < group.skills.length; i += chunkSize) {
      const chunk = group.skills.slice(i, i + chunkSize);
      blocks.push({
        html: this._sectionRowsHtml(chunk, i),
        label: `${group.type} (rows ${i + 1}-${i + chunk.length})`,
        skillCount: chunk.length,
      });
    }
    blocks.push({
      html: this._sectionFooterHtml(group),
      label: `${group.type} (average)`,
      skillCount: group.skills.length,
    });
    return blocks;
  },

  _summaryBlockHtml(data, result) {
    const c = this.COLORS;
    const { skills, levelComp } = data;
    const tested = result.tested;
    const passedCount    = tested.filter(s => Number(s.latestScore) >= 5.0).length;
    const failedCount    = result.failed.length;
    const notTestedCount = skills.length - tested.length;
    const avgText = result.avg !== null ? result.avg.toFixed(1) : '—';

    let statusBanner = '';
    if (result.status === 'failed') {
      statusBanner = `
        <div style="background:${c.failed};color:#ffffff;font-weight:700;font-size:12px;padding:8px 12px;border-radius:6px;margin-bottom:8px">
          ❌ Failed &mdash; ${result.failed.length} skill${result.failed.length !== 1 ? 's' : ''} scored below 5.0
        </div>
        <div style="font-size:10.5px;color:${c.failed};margin-bottom:10px">
          ${result.failed.map(s => App.escHtml(s.name)).join(', ')}
        </div>`;
    } else if (result.status === 'incomplete') {
      statusBanner = `
        <div style="background:${c.incomplete};color:#ffffff;font-weight:700;font-size:12px;padding:8px 12px;border-radius:6px;margin-bottom:10px">
          Incomplete &mdash; ${tested.length} of ${skills.length} skills tested
        </div>`;
    }

    const notesHtml = levelComp?.notes
      ? `<div style="font-size:11px;color:${c.textPrimary};line-height:1.6;white-space:pre-wrap">${App.escHtml(levelComp.notes)}</div>`
      : Array.from({ length: 5 }).map(() =>
          `<div style="border-bottom:1px solid ${c.border};height:22px"></div>`
        ).join('');

    return `
      <div style="font-family:Helvetica,Arial,sans-serif;color:${c.textPrimary};background:#ffffff">
        <div style="background:${c.rowAlt};border:1px solid ${c.border};border-radius:6px;padding:12px 16px">
          <div style="font-size:13px;font-weight:700;margin-bottom:8px">Summary</div>
          ${statusBanner}
          <table style="width:100%;border-collapse:collapse;font-size:11px">
            <tr>
              <td style="padding:2px 0;color:${c.textSecondary}">Skills Tested</td>
              <td style="padding:2px 0;font-weight:600">${tested.length} of ${skills.length} skills tested</td>
            </tr>
            <tr>
              <td style="padding:2px 0;color:${c.textSecondary}">Passed / Failed / Not Tested</td>
              <td style="padding:2px 0;font-weight:600">${passedCount} passed &middot; ${failedCount} failed &middot; ${notTestedCount} not tested</td>
            </tr>
            <tr>
              <td style="padding:2px 0;color:${c.textSecondary}">Overall Average</td>
              <td style="padding:2px 0;font-weight:600">${avgText}</td>
            </tr>
            <tr>
              <td style="padding:2px 0;color:${c.textSecondary}">Designation</td>
              <td style="padding:2px 0;font-weight:600">${result.label}</td>
            </tr>
          </table>
        </div>

        <div style="margin-top:18px">
          <div style="font-size:13px;font-weight:700;margin-bottom:6px">Coach Comments</div>
          ${notesHtml}
        </div>
      </div>`;
  },

  // Full report as one HTML string — used only for on-screen preview/debug;
  // actual PDF assembly renders each block separately (see _renderPdfDocument).
  buildReportHtml(data) {
    const result = this.computeResult(data.skills);
    const groups = this._groupByType(data.skills);
    return `
      <div style="padding:36px">
        ${this._headerBlockHtml(data, result)}
        ${groups.map(g => this._sectionBlockHtml(g)).join('')}
        ${this._summaryBlockHtml(data, result)}
      </div>`;
  },

  // =============================================
  // PDF ASSEMBLY — one html2canvas capture per block, placed with a running
  // Y-position tracker (see page-break strategy note at the top of the file)
  // =============================================

  _isMobile() {
    return /Mobi|Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
  },

  _isIOSSafari() {
    const ua = navigator.userAgent;
    return /iPad|iPhone|iPod/.test(ua) && !/CriOS|FxiOS|EdgiOS/.test(ua);
  },

  // Lower resolution on mobile — same fixed 900px "device" width, just a
  // smaller multiplier — cuts per-canvas memory/GPU load on iOS Safari,
  // which is the likeliest source of the stalls seen there. Levels with an
  // unusually high total skill count (more captures overall) get an extra
  // step down, since accumulated memory pressure across the report is the
  // greater risk than any single capture's resolution.
  _captureScale(isLargeLevel) {
    if (!this._isMobile()) return 2;
    return isLargeLevel ? 1.0 : 1.5;
  },

  async _captureBlock(html, blockWidthPx, isLargeLevel) {
    const container = document.createElement('div');
    container.style.cssText = `position:fixed;left:-99999px;top:0;width:${blockWidthPx}px;background:#ffffff`;
    container.innerHTML = html;
    document.body.appendChild(container);
    try {
      return await html2canvas(container, {
        scale: this._captureScale(isLargeLevel),
        backgroundColor: '#ffffff',
        useCORS: true,
        allowTaint: false,
        logging: false,
        imageTimeout: 15000,
        removeContainer: true,
      });
    } finally {
      document.body.removeChild(container);
    }
  },

  // Races a promise against a timeout so a stalled html2canvas call (which
  // can hang on iOS Safari rather than reject) can't leave the caller's
  // await — and therefore its button-loading state — stuck forever.
  _withTimeout(promise, ms, message) {
    let timer;
    const timeout = new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(message)), ms);
    });
    return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
  },

  // Last-resort path for iOS Safari when canvas-based generation fails or
  // times out: render the same report blocks into a hidden container and
  // use the browser's native print dialog (Save as PDF) instead of jsPDF.
  _printFallback(data) {
    const result = this.computeResult(data.skills);
    const groups = this._groupByType(data.skills);
    const html = `
      ${this._headerBlockHtml(data, result)}
      ${groups.map(g => this._sectionBlockHtml(g)).join('')}
      ${this._summaryBlockHtml(data, result)}
    `;

    let container = document.getElementById('dive-drills-print-report');
    if (!container) {
      container = document.createElement('div');
      container.id = 'dive-drills-print-report';
      document.body.appendChild(container);
    }
    container.innerHTML = `<div style="max-width:800px;margin:0 auto;padding:24px">${html}</div>`;

    let style = document.getElementById('dive-drills-print-style');
    if (!style) {
      style = document.createElement('style');
      style.id = 'dive-drills-print-style';
      document.head.appendChild(style);
    }
    style.textContent = `
      @media print {
        body > :not(#dive-drills-print-report) { display: none !important; }
        #dive-drills-print-report { display: block !important; }
      }
      @media screen {
        #dive-drills-print-report { display: none; }
      }
    `;

    const cleanup = () => {
      container.innerHTML = '';
      window.removeEventListener('afterprint', cleanup);
    };
    window.addEventListener('afterprint', cleanup);
    window.print();
  },

  // Draws one already-captured canvas onto the doc, slicing it across as
  // many pages as needed — used both for a normal block and as the fallback
  // for the rare block taller than a full page.
  _placeCanvasSliced(doc, canvas, x, startY, widthPt, pxPerPt, maxHeightPt, pageHeight, margin, footerReserve) {
    let renderedPx = 0;
    let y = startY;
    let availablePt = maxHeightPt;
    while (renderedPx < canvas.height) {
      const availablePx = availablePt * pxPerPt;
      const sliceHeightPx = Math.min(availablePx, canvas.height - renderedPx);

      const pageCanvas = document.createElement('canvas');
      pageCanvas.width  = canvas.width;
      pageCanvas.height = sliceHeightPx;
      const ctx = pageCanvas.getContext('2d');
      ctx.fillStyle = '#ffffff';
      ctx.fillRect(0, 0, pageCanvas.width, pageCanvas.height);
      ctx.drawImage(canvas, 0, renderedPx, canvas.width, sliceHeightPx, 0, 0, canvas.width, sliceHeightPx);

      const sliceHeightPt = sliceHeightPx / pxPerPt;
      doc.addImage(pageCanvas.toDataURL('image/jpeg', 0.92), 'JPEG', x, y, widthPt, sliceHeightPt);

      renderedPx += sliceHeightPx;
      if (renderedPx < canvas.height) {
        doc.addPage();
        y = margin;
        availablePt = pageHeight - margin * 2 - footerReserve;
      } else {
        y += sliceHeightPt;
      }
    }
    return y;
  },

  async _renderPdfDocument(data) {
    const { jsPDF } = window.jspdf;
    const doc = new jsPDF({ unit: 'pt', format: 'letter' });
    const pageWidth     = doc.internal.pageSize.getWidth();
    const pageHeight    = doc.internal.pageSize.getHeight();
    const margin        = 54; // 0.75in
    const footerReserve = 34;
    const blockGap       = 10;
    const contentWidth  = pageWidth - margin * 2;
    const blockWidthPx  = 900; // fixed "device" width — keeps scaling consistent across every block

    const result = this.computeResult(data.skills);
    const groups = this._groupByType(data.skills);

    const blocks = [
      { html: this._headerBlockHtml(data, result), label: 'Header', skillCount: null },
      ...groups.flatMap(g => this._buildSectionBlocks(g)),
      { html: this._summaryBlockHtml(data, result), label: 'Summary', skillCount: null },
    ];

    const isMobile      = this._isMobile();
    const isLargeLevel  = data.skills.length > this.LARGE_LEVEL_SKILL_THRESHOLD;
    const captureDelayMs = isLargeLevel ? 150 : 80;

    let y = margin;
    let firstBlockOnPage = true;
    for (const block of blocks) {
      console.log('Capturing section:', block.label, 'skills count:', block.skillCount);
      const canvas   = await this._captureBlock(block.html, blockWidthPx, isLargeLevel);
      // Give iOS Safari a beat to release the previous canvas before the
      // next capture — cheap insurance against memory pressure building up
      // across a multi-section report. Large levels get a longer delay
      // since they produce more captures overall.
      if (isMobile) await new Promise(r => setTimeout(r, captureDelayMs));
      const pxPerPt  = canvas.width / contentWidth;
      const blockHeightPt = canvas.height / pxPerPt;
      const pageContentHeightPt = pageHeight - margin * 2 - footerReserve;

      if (!firstBlockOnPage && y + blockHeightPt > pageHeight - margin - footerReserve) {
        doc.addPage();
        y = margin;
        firstBlockOnPage = true;
      }

      if (blockHeightPt > pageContentHeightPt) {
        // Rare: a single block (e.g. a very long section) is itself taller
        // than one page — fall back to slicing just that block.
        y = this._placeCanvasSliced(doc, canvas, margin, y, contentWidth, pxPerPt, pageContentHeightPt, pageHeight, margin, footerReserve);
      } else {
        doc.addImage(canvas.toDataURL('image/jpeg', 0.92), 'JPEG', margin, y, contentWidth, blockHeightPt);
        y += blockHeightPt;
      }
      y += blockGap;
      firstBlockOnPage = false;
    }

    const totalPages = doc.internal.getNumberOfPages();
    const generatedStr = new Date().toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
    for (let i = 1; i <= totalPages; i++) {
      doc.setPage(i);
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(8);
      doc.setTextColor(102, 102, 102);
      doc.text('Generated by Dive Drills - divedrills.com', margin, pageHeight - 24);
      doc.text(`Generated ${generatedStr}`, margin, pageHeight - 14);
      doc.text('Upstate Diving - Confidential', pageWidth - margin, pageHeight - 24, { align: 'right' });
      if (totalPages > 1) {
        doc.text(`Page ${i} of ${totalPages}`, pageWidth - margin, pageHeight - 14, { align: 'right' });
      }
    }

    return doc;
  },

  _fileName(data) {
    const last = (data.diver.last_name || data.diver.full_name || 'diver').replace(/[^a-z0-9]+/gi, '_');
    return `DiveDrills_Report_${last}_Level${data.level}.pdf`;
  },

  // =============================================
  // PUBLIC ACTIONS
  // =============================================

  // Returns { printed } — printed:true means html2canvas failed/stalled and
  // we fell back to the browser print dialog on iOS Safari instead of a
  // download; callers should show different confirmation copy for that case.
  async downloadTestReport(diverId, level) {
    const data = await this.gatherReportData(diverId, level);
    try {
      const doc = await this._withTimeout(
        this._renderPdfDocument(data),
        this.PDF_TIMEOUT_MS,
        'PDF generation is taking longer than expected. Please try again.'
      );
      doc.save(this._fileName(data));
      return { printed: false };
    } catch (err) {
      if (this._isIOSSafari()) {
        this._printFallback(data);
        return { printed: true };
      }
      throw err;
    }
  },

  async getReportPdfBase64(diverId, level) {
    const data = await this.gatherReportData(diverId, level);
    const doc = await this._withTimeout(
      this._renderPdfDocument(data),
      this.PDF_TIMEOUT_MS,
      'PDF generation is taking longer than expected. Please try again.'
    );
    return { base64: doc.output('datauristring').split(',')[1], fileName: this._fileName(data), data };
  },

  async emailTestReport({ diverId, level, parentEmail, parentName, coachName, coachMessage }) {
    const { base64, fileName, data } = await this.getReportPdfBase64(diverId, level);
    const diverName = App.formatNameLastFirst(data.diver) || data.diver.full_name;

    const res = await fetch('/.netlify/functions/send-report-email', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        parentEmail, parentName, diverName, level, coachName, coachMessage,
        pdfBase64: base64, fileName,
      }),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok || !body.success) throw new Error(body.error || 'Failed to send report email.');
    return body;
  },

  // =============================================
  // REPORTS PAGE (stats.html) — list of available reports
  // =============================================

  async getReportsListData() {
    const rows = await SupabaseDB.getAllLevelCompletionsWithDiverInfo();
    return rows.map(r => ({
      diverId:      r.diver_id,
      diverName:    App.formatNameLastFirst(r.diver) || r.diver?.full_name || 'Unknown diver',
      level:        r.level,
      designation:  r.designation,
      passed:       r.passed,
      lastTestDate: r.completed_at,
      coachName:    r.coach?.full_name || '—',
    }));
  },
};
