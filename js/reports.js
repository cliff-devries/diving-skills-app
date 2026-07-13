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
//     — a full level's skill types realistically hold a handful of skills
//     each, never more than fits on one page, so section-level atomicity
//     already guarantees no split/orphaned rows at a fraction of the cost.
// =============================================

const Reports = {

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
  // PASS / FAIL / INCOMPLETE — computed fresh from the skills list every
  // time (not from the stored level_completions.designation/passed), so a
  // single retest is reflected immediately without needing that row
  // recomputed. Checked in order: incomplete, then failed, then average tier.
  // =============================================

  computeResult(skills) {
    const c = this.COLORS;
    const total   = skills.length;
    const tested  = skills.filter(s => s.latestScore != null);
    const failed  = tested.filter(s => Number(s.latestScore) < 5.0);
    const avg     = tested.length
      ? tested.reduce((sum, s) => sum + Number(s.latestScore), 0) / tested.length
      : null;

    if (total === 0 || tested.length < total) {
      return { status: 'incomplete', label: 'INCOMPLETE', bg: c.incomplete, color: '#ffffff', tested, failed, avg };
    }
    if (failed.length > 0) {
      return { status: 'failed', label: 'FAILED', bg: c.failed, color: '#ffffff', tested, failed, avg };
    }
    if (avg >= 9.0) return { status: 'gold',   label: '🥇 Gold',   bg: c.gold,   color: '#1a1a1a', tested, failed, avg };
    if (avg >= 8.0) return { status: 'silver', label: '🥈 Silver', bg: c.silver, color: '#1a1a1a', tested, failed, avg };
    if (avg >= 7.0) return { status: 'bronze', label: '🥉 Bronze', bg: c.bronze, color: '#ffffff', tested, failed, avg };
    return { status: 'passed', label: '✅ Passed', bg: c.passed, color: '#ffffff', tested, failed, avg };
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
    const tested = skill.latestScore != null;
    const scoreText = tested ? Number(skill.latestScore).toFixed(1) : '—';
    const icon = !tested ? '' : (skill.latestScore >= 5.0 ? '✅' : '❌');
    return `
      <tr style="background:${bg}">
        <td style="padding:6px 10px;font-size:11px;color:${c.textPrimary};border-bottom:1px solid ${c.border}">${App.escHtml(skill.name)}</td>
        <td style="padding:6px 10px;font-size:11px;color:${c.textPrimary};border-bottom:1px solid ${c.border};text-align:center;width:60px">${scoreText}</td>
        <td style="padding:6px 10px;font-size:13px;border-bottom:1px solid ${c.border};text-align:center;width:40px">${icon}</td>
      </tr>`;
  },

  // Section average only counts tested skills — untested ('—') skills don't
  // pull it down, and a section with nothing tested yet shows '—'.
  _sectionBlockHtml(group) {
    const c = this.COLORS;
    const tested = group.skills.filter(s => s.latestScore != null);
    const avg = tested.length
      ? (tested.reduce((sum, s) => sum + Number(s.latestScore), 0) / tested.length).toFixed(1)
      : null;
    return `
      <div style="font-family:Helvetica,Arial,sans-serif;background:#ffffff">
        <div style="background:${c.accent};color:#ffffff;font-weight:700;font-size:12px;padding:6px 10px;letter-spacing:0.03em;text-transform:uppercase">
          ${App.escHtml(group.type)}
        </div>
        <table style="width:100%;border-collapse:collapse">
          <tbody>${group.skills.map((s, i) => this._skillRowHtml(s, i)).join('')}</tbody>
        </table>
        <div style="text-align:right;font-size:10.5px;color:${c.textSecondary};padding:4px 10px;font-style:italic">
          Section Average: ${avg !== null ? avg : '—'}
        </div>
      </div>`;
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

  async _captureBlock(html, blockWidthPx) {
    const container = document.createElement('div');
    container.style.cssText = `position:fixed;left:-99999px;top:0;width:${blockWidthPx}px;background:#ffffff`;
    container.innerHTML = html;
    document.body.appendChild(container);
    try {
      return await html2canvas(container, { scale: 2, backgroundColor: '#ffffff', useCORS: true });
    } finally {
      document.body.removeChild(container);
    }
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

    const blockHtmls = [
      this._headerBlockHtml(data, result),
      ...groups.map(g => this._sectionBlockHtml(g)),
      this._summaryBlockHtml(data, result),
    ];

    let y = margin;
    let firstBlockOnPage = true;
    for (const html of blockHtmls) {
      const canvas   = await this._captureBlock(html, blockWidthPx);
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

  async downloadTestReport(diverId, level) {
    const data = await this.gatherReportData(diverId, level);
    const doc = await this._renderPdfDocument(data);
    doc.save(this._fileName(data));
  },

  async getReportPdfBase64(diverId, level) {
    const data = await this.gatherReportData(diverId, level);
    const doc = await this._renderPdfDocument(data);
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
