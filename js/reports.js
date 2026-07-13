// =============================================
// DIVE DRILLS — Test Report PDF generation
// Builds a light/white-theme PDF test report for one diver/level from the
// current database state (skills, skill_completions, level_completions).
// No storage — always generated fresh, so a retest is reflected immediately.
// Requires jsPDF + html2canvas (loaded via CDN) on any page that uses this.
// =============================================

const Reports = {

  SECTION_ORDER: [
    'Basics', 'Conditioning', 'Flexibility', 'Trampoline', 'Trampoline in Belt',
    'Dryboard', 'Dryboard in Belt', 'Dry Platform', '1m Platform', '1m Platform in Belt',
    '1m Springboard', '3m Springboard', 'Platform', 'Pool', 'Games', 'Bonus',
  ],

  COLORS: {
    accent:     '#00c9a7',
    textPrimary:   '#1a1a1a',
    textSecondary: '#666666',
    rowAlt:     '#f9f9f9',
    border:     '#e0e0e0',
    gold:       '#f5c518',
    silver:     '#c0c0c0',
    bronze:     '#cd7f32',
    passed:     '#00c9a7',
    notPassed:  '#e05252',
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
  // HTML TEMPLATE (rasterized by html2canvas, then paginated into the PDF)
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

  _designationInfo(levelComp) {
    const c = this.COLORS;
    if (!levelComp) return { label: '⏳ In Progress', bg: '#999999', color: '#ffffff' };
    if (levelComp.passed === false) return { label: '❌ Not Passed', bg: c.notPassed, color: '#ffffff' };
    if (levelComp.designation === 'gold')   return { label: '🥇 Gold',   bg: c.gold,   color: '#1a1a1a' };
    if (levelComp.designation === 'silver') return { label: '🥈 Silver', bg: c.silver, color: '#1a1a1a' };
    if (levelComp.designation === 'bronze') return { label: '🥉 Bronze', bg: c.bronze, color: '#ffffff' };
    return { label: '✅ Passed', bg: c.passed, color: '#ffffff' };
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

  _sectionHtml(group) {
    const c = this.COLORS;
    const tested = group.skills.filter(s => s.latestScore != null);
    const avg = tested.length
      ? (tested.reduce((sum, s) => sum + Number(s.latestScore), 0) / tested.length).toFixed(1)
      : null;
    return `
      <div style="margin-top:14px">
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

  buildReportHtml(data) {
    const { diver, skills, levelComp, coach, level } = data;
    const c = this.COLORS;

    const age  = this._calcAge(diver.date_of_birth);
    const dob  = this._formatDate(diver.date_of_birth);
    const name = App.formatNameLastFirst(diver) || diver.full_name || '';
    const initials = Auth.getInitials(diver.full_name || '');

    const tested = skills.filter(s => s.latestScore != null);
    const testDates = tested.map(s => s.latestTestDate).filter(Boolean).sort();
    const mostRecentTestDate = testDates.length ? testDates[testDates.length - 1] : null;

    const passedCount    = tested.filter(s => Number(s.latestScore) >= 5.0).length;
    const failedCount    = tested.filter(s => Number(s.latestScore) < 5.0).length;
    const notTestedCount = skills.length - tested.length;
    const overallAvg = tested.length
      ? (tested.reduce((sum, s) => sum + Number(s.latestScore), 0) / tested.length).toFixed(1)
      : null;

    const desig = this._designationInfo(levelComp);
    const groups = this._groupByType(skills);

    const notesHtml = levelComp?.notes
      ? `<div style="font-size:11px;color:${c.textPrimary};line-height:1.6;white-space:pre-wrap">${App.escHtml(levelComp.notes)}</div>`
      : Array.from({ length: 5 }).map(() =>
          `<div style="border-bottom:1px solid ${c.border};height:22px"></div>`
        ).join('');

    return `
      <div style="font-family:Helvetica,Arial,sans-serif;color:${c.textPrimary};width:100%;box-sizing:border-box;padding:36px;background:#ffffff">

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
          <div style="background:${desig.bg};color:${desig.color};font-weight:700;font-size:12px;padding:6px 14px;border-radius:14px;white-space:nowrap">
            ${desig.label}
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

        <div style="height:1px;background:${c.border};margin:14px 0"></div>

        ${groups.map(g => this._sectionHtml(g)).join('')}

        <div style="height:1px;background:${c.border};margin:18px 0 12px"></div>

        <div style="background:${c.rowAlt};border:1px solid ${c.border};border-radius:6px;padding:12px 16px">
          <div style="font-size:13px;font-weight:700;margin-bottom:8px">Summary</div>
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
              <td style="padding:2px 0;font-weight:600">${overallAvg !== null ? overallAvg : '—'}</td>
            </tr>
            <tr>
              <td style="padding:2px 0;color:${c.textSecondary}">Designation</td>
              <td style="padding:2px 0;font-weight:600">${desig.label}</td>
            </tr>
          </table>
        </div>

        <div style="margin-top:18px">
          <div style="font-size:13px;font-weight:700;margin-bottom:6px">Coach Comments</div>
          ${notesHtml}
        </div>

      </div>`;
  },

  // =============================================
  // PDF ASSEMBLY (html2canvas → sliced jsPDF pages + vector footer)
  // =============================================

  async _renderPdfDocument(data) {
    const { jsPDF } = window.jspdf;
    const doc = new jsPDF({ unit: 'pt', format: 'letter' });
    const pageWidth     = doc.internal.pageSize.getWidth();
    const pageHeight    = doc.internal.pageSize.getHeight();
    const margin        = 54; // 0.75in
    const footerReserve = 34;
    const contentWidth  = pageWidth - margin * 2;

    const container = document.createElement('div');
    container.style.cssText = 'position:fixed;left:-99999px;top:0;width:900px;background:#ffffff';
    container.innerHTML = this.buildReportHtml(data);
    document.body.appendChild(container);

    try {
      const canvas = await html2canvas(container, { scale: 2, backgroundColor: '#ffffff', useCORS: true });
      const pxPerPt = canvas.width / contentWidth;
      const pageContentHeightPx = (pageHeight - margin * 2 - footerReserve) * pxPerPt;

      let renderedPx = 0;
      let pageIndex  = 0;
      while (renderedPx < canvas.height) {
        if (pageIndex > 0) doc.addPage();
        const sliceHeightPx = Math.min(pageContentHeightPx, canvas.height - renderedPx);

        const pageCanvas = document.createElement('canvas');
        pageCanvas.width  = canvas.width;
        pageCanvas.height = sliceHeightPx;
        const pageCtx = pageCanvas.getContext('2d');
        // JPEG has no alpha channel — fill white first so any transparent
        // edge pixels don't turn black when flattened.
        pageCtx.fillStyle = '#ffffff';
        pageCtx.fillRect(0, 0, pageCanvas.width, pageCanvas.height);
        pageCtx.drawImage(
          canvas, 0, renderedPx, canvas.width, sliceHeightPx,
          0, 0, canvas.width, sliceHeightPx
        );

        // jsPDF re-encodes PNG as a near-raw bitmap internally (a ~1800x1580
        // page here bloated a 259KB PNG into an ~11MB PDF) — JPEG is embedded
        // directly via DCTDecode instead, keeping file size sane for email/mobile.
        const sliceHeightPt = sliceHeightPx / pxPerPt;
        doc.addImage(pageCanvas.toDataURL('image/jpeg', 0.92), 'JPEG', margin, margin, contentWidth, sliceHeightPt);

        renderedPx += sliceHeightPx;
        pageIndex++;
      }
    } finally {
      document.body.removeChild(container);
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
