#!/usr/bin/env node
// Ticket Dashboard — Kanban board from project tickets
// Usage:
//   node tools/ticket-dashboard.js          → generate dashboard.html + open
//   node tools/ticket-dashboard.js --serve   → serve with live reload
//   node tools/ticket-dashboard.js --serve 9090  → serve on port 9090

const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// ---------------------------------------------------------------------------
// Config Loading
// ---------------------------------------------------------------------------

// Walk up from script dir to find harness-config.json (project root)
function findConfig() {
  let dir = process.cwd();
  for (let i = 0; i < 10; i++) {
    const candidate = path.join(dir, 'harness-config.json');
    if (fs.existsSync(candidate)) {
      try { return JSON.parse(fs.readFileSync(candidate, 'utf8')); } catch (e) { /* fall through */ }
    }
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return {};
}

const CONFIG = findConfig();
const TICKET_CONFIG = CONFIG.tickets || {};
const DASH_CONFIG = CONFIG.dashboard || {};

// Resolve ticket directory relative to cwd
const TICKETS_DIR = path.resolve(process.cwd(), TICKET_CONFIG.directory || 'project/tickets');
const CLOSED_DIR = path.join(TICKETS_DIR, 'closed');
const OUTPUT = path.join(process.cwd(), 'tools', 'dashboard.html');

// Statuses and priorities from config with defaults
const STATUSES = TICKET_CONFIG.statuses || ['BACKLOG', 'NOT_SPECCED', 'SPEC_READY', 'IN_PROGRESS', 'IN_REVIEW', 'NEEDS_HUMAN'];
const PRIORITIES = TICKET_CONFIG.priorities || ['P0', 'P1', 'P2', 'P3', 'P5'];

// Default colors — overridable via config
const DEFAULT_STATUS_COLORS = {
  BACKLOG: '#6b7280', NOT_SPECCED: '#f59e0b', SPEC_READY: '#3b82f6',
  IN_PROGRESS: '#8b5cf6', IN_REVIEW: '#10b981', NEEDS_HUMAN: '#ef4444', CLOSED: '#22c55e'
};
const DEFAULT_PRI_COLORS = { P0: '#dc2626', P1: '#ea580c', P2: '#ca8a04', P3: '#2563eb', P5: '#6b7280' };

const STATUS_COLORS = Object.assign({}, DEFAULT_STATUS_COLORS, DASH_CONFIG.statusColors || {});
const PRI_COLORS = Object.assign({}, DEFAULT_PRI_COLORS, DASH_CONFIG.priorityColors || {});

// Status display labels
const STATUS_LABELS = {
  BACKLOG: 'Backlog', NOT_SPECCED: 'Not Specced', SPEC_READY: 'Spec Ready',
  IN_PROGRESS: 'In Progress', IN_REVIEW: 'In Review', NEEDS_HUMAN: 'Needs Human', CLOSED: 'Closed'
};

// Parse CLI args
const args = process.argv.slice(2);
const SERVE = args.includes('--serve') || args.some(a => /^\d+$/.test(a));
const PORT = (() => {
  for (const a of args) { if (/^\d+$/.test(a)) return parseInt(a, 10); }
  return DASH_CONFIG.port || 4000;
})();

// ---------------------------------------------------------------------------
// Ticket Parser
// ---------------------------------------------------------------------------

// Extract field value from markdown line patterns
function extractField(lines, fieldName) {
  for (const line of lines) {
    const l = line.trim();
    // **Field:** value
    const bold = new RegExp('^\\*\\*' + fieldName + ':\\*\\*\\s*(.+)', 'i');
    const boldMatch = l.match(bold);
    if (boldMatch) return boldMatch[1].trim();
    // ## Field: value
    const heading = new RegExp('^##\\s*' + fieldName + ':\\s*(.+)', 'i');
    const headingMatch = l.match(heading);
    if (headingMatch) return headingMatch[1].trim();
  }
  return '';
}

// Normalize priority to P0-P5 format
function normalizePriority(raw) {
  if (!raw) return '';
  const upper = raw.toUpperCase().trim();
  if (/^P\d$/.test(upper)) return upper;
  const map = { CRITICAL: 'P0', HIGH: 'P1', MEDIUM: 'P3', LOW: 'P5' };
  for (const [key, val] of Object.entries(map)) {
    if (upper.includes(key)) return val;
  }
  return '';
}

// Normalize status to canonical values
function normalizeStatus(raw) {
  if (!raw) return '';
  let s = raw.toUpperCase().replace(/[^A-Z_\s]/g, '').trim().replace(/\s+/g, '_');
  const map = {
    COMPLETE: 'CLOSED', CLOSED: 'CLOSED', DONE: 'CLOSED',
    SPEC_COMPLETE: 'SPEC_READY', READY: 'SPEC_READY',
    TODO: 'BACKLOG', NOT_STARTED: 'BACKLOG',
    BLOCKED: 'NEEDS_HUMAN', NEEDS_INFRA: 'NEEDS_HUMAN',
    CODE_COMPLETE: 'IN_REVIEW', PARTIAL: 'IN_PROGRESS'
  };
  return map[s] || s;
}

function parseTicket(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const name = path.basename(filePath, '.md');
  const lines = content.split('\n');

  // Title: first H1
  let title = '';
  for (const line of lines) {
    if (line.startsWith('# ')) {
      title = line.replace(/^#+\s*/, '').replace(/^TICKET:\s*/i, '').trim();
      break;
    }
  }
  if (!title) title = name.replace(/^TICKET-/, '').replace(/-/g, ' ');

  const priority = normalizePriority(extractField(lines, 'Priority'));
  let status = normalizeStatus(extractField(lines, 'Status'));
  const spec = extractField(lines, 'Spec');
  const completed = extractField(lines, 'Completed');
  const notes = extractField(lines, 'Notes');
  const assignedTo = extractField(lines, 'Assigned To');
  const release = extractField(lines, 'Release');

  return { name, file: filePath, title, priority, status, spec, completed, notes, assignedTo, release };
}

// ---------------------------------------------------------------------------
// Data Loading
// ---------------------------------------------------------------------------

function loadTickets() {
  const tickets = [];

  if (fs.existsSync(TICKETS_DIR)) {
    for (const f of fs.readdirSync(TICKETS_DIR)) {
      if (f.endsWith('.md') && f.startsWith('TICKET-')) {
        try { tickets.push(parseTicket(path.join(TICKETS_DIR, f))); } catch (e) { /* skip */ }
      }
    }
  }

  if (fs.existsSync(CLOSED_DIR)) {
    for (const f of fs.readdirSync(CLOSED_DIR)) {
      if (f.endsWith('.md') && f.startsWith('TICKET-')) {
        try {
          const t = parseTicket(path.join(CLOSED_DIR, f));
          t.status = 'CLOSED';
          tickets.push(t);
        } catch (e) { /* skip */ }
      }
    }
  }

  return tickets;
}

// Load SESSION_STATE.md if it exists (one level up from tickets dir)
function loadSessionState() {
  const sessionPath = path.join(TICKETS_DIR, '..', 'SESSION_STATE.md');
  if (!fs.existsSync(sessionPath)) return null;
  try {
    const content = fs.readFileSync(sessionPath, 'utf8');
    const lines = content.split('\n');
    const extract = (field) => {
      for (const line of lines) {
        const l = line.trim();
        const m = l.match(new RegExp('^\\*\\*' + field + ':\\*\\*\\s*(.+)', 'i'))
               || l.match(new RegExp('^' + field + ':\\s*(.+)', 'i'));
        if (m) return m[1].trim();
      }
      return '';
    };
    return {
      version: extract('Version') || extract('Current Version'),
      branch: extract('Branch') || extract('Current Branch'),
      tests: extract('Tests') || extract('Test Status'),
      lastUpdated: extract('Last Updated') || extract('Updated')
    };
  } catch (e) { return null; }
}

// ---------------------------------------------------------------------------
// HTML Generation
// ---------------------------------------------------------------------------

function esc(s) {
  if (!s) return '';
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function buildPage(tickets) {
  const now = new Date().toLocaleString('en-CA', { dateStyle: 'medium', timeStyle: 'short' });
  const session = loadSessionState();
  const projectName = (CONFIG.project && CONFIG.project.name) || 'Project';

  // Build column definitions from config statuses
  const columns = STATUSES.map(id => ({
    id, label: STATUS_LABELS[id] || id.replace(/_/g, ' '), color: STATUS_COLORS[id] || '#6b7280'
  }));

  // Serialize data for client-side rendering
  const ticketData = JSON.stringify(tickets.map(t => ({
    n: t.name, t: t.title, p: t.priority, s: t.status,
    a: t.assignedTo || '', sp: t.spec ? 1 : 0,
    c: t.completed || '', no: t.notes || '', r: (t.release || '').toLowerCase()
  })));

  const columnsJson = JSON.stringify(columns);
  const priColorsJson = JSON.stringify(PRI_COLORS);
  const sessionJson = session ? JSON.stringify(session) : 'null';

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><rect width='32' height='32' rx='6' fill='%231a1a2e'/><polyline points='4,24 10,18 16,20 22,10 28,6' fill='none' stroke='%2322c55e' stroke-width='3' stroke-linecap='round' stroke-linejoin='round'/><circle cx='28' cy='6' r='2.5' fill='%2322c55e'/></svg>">
<title>${esc(projectName)} Dashboard</title>
<style>
  *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }

  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: #1a1a2e;
    color: #e2e8f0;
    min-height: 100vh;
    line-height: 1.5;
  }

  ::-webkit-scrollbar { width: 6px; height: 6px; }
  ::-webkit-scrollbar-track { background: transparent; }
  ::-webkit-scrollbar-thumb { background: #334155; border-radius: 3px; }
  ::-webkit-scrollbar-thumb:hover { background: #475569; }

  /* ---- Header ---- */
  .header-bar {
    background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
    border-bottom: 2px solid #3b82f6;
    padding: 10px 24px;
    display: flex;
    align-items: center;
    gap: 16px;
    flex-wrap: wrap;
    position: sticky;
    top: 0;
    z-index: 100;
  }
  .header-bar h1 {
    font-size: 14px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 2px;
    color: #3b82f6;
    white-space: nowrap;
    flex-shrink: 0;
  }
  .global-filters {
    display: flex;
    align-items: center;
    gap: 12px;
    flex: 1;
    flex-wrap: wrap;
  }
  .global-filters select, .global-filters input {
    background: #1a1a2e;
    color: #e2e8f0;
    border: 1px solid #334155;
    border-radius: 4px;
    padding: 5px 10px;
    font-size: 11px;
    font-family: inherit;
  }
  .global-filters select:focus, .global-filters input:focus {
    outline: none;
    border-color: #3b82f6;
  }
  .global-filters input { width: 200px; }
  .header-status {
    margin-left: auto;
    font-size: 10px;
    color: #64748b;
    text-transform: uppercase;
    letter-spacing: 1px;
    white-space: nowrap;
    flex-shrink: 0;
  }
  .header-status .live-dot {
    display: inline-block;
    width: 6px; height: 6px;
    border-radius: 50%;
    background: #22c55e;
    margin-right: 4px;
    animation: pulse 2s infinite;
  }
  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
  }

  /* ---- Session State Panel ---- */
  .session-panel {
    margin: 16px 32px 0;
    background: #16213e;
    border: 1px solid #334155;
    border-radius: 8px;
    padding: 12px 16px;
    display: flex;
    gap: 24px;
    flex-wrap: wrap;
    align-items: center;
  }
  .session-item {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 12px;
  }
  .session-label {
    color: #64748b;
    text-transform: uppercase;
    font-size: 10px;
    font-weight: 600;
    letter-spacing: 0.5px;
  }
  .session-value {
    color: #e2e8f0;
    font-family: 'SF Mono', 'Fira Code', Menlo, Consolas, monospace;
    font-size: 12px;
  }
  .session-value.ok { color: #22c55e; }
  .session-value.warn { color: #f59e0b; }

  /* ---- Hero Stats ---- */
  .hero {
    padding: 16px 32px;
    display: flex;
    gap: 16px;
    align-items: stretch;
  }

  /* Status bar */
  .status-bar-section {
    flex: 1;
    background: #16213e;
    border: 1px solid #334155;
    border-radius: 12px;
    padding: 14px 16px;
  }
  .status-bar-header {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
    margin-bottom: 10px;
  }
  .status-bar-title {
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: #94a3b8;
  }
  .status-bar-total {
    font-size: 20px;
    font-weight: 800;
    color: #fff;
  }
  .status-bar-total small {
    font-size: 11px;
    font-weight: 400;
    color: #64748b;
    margin-left: 4px;
  }
  .status-bar-wrap {
    display: flex;
    height: 16px;
    border-radius: 8px;
    overflow: hidden;
    background: #1a1a2e;
  }
  .status-bar-seg {
    height: 100%;
    min-width: 2px;
    transition: width 0.4s ease;
  }
  .status-bar-seg:first-child { border-radius: 8px 0 0 8px; }
  .status-bar-seg:last-child { border-radius: 0 8px 8px 0; }
  .status-bar-legend {
    display: flex;
    flex-wrap: wrap;
    gap: 4px 14px;
    margin-top: 8px;
  }
  .legend-item {
    display: flex;
    align-items: center;
    gap: 5px;
    font-size: 11px;
    color: #94a3b8;
  }
  .legend-dot {
    width: 8px;
    height: 8px;
    border-radius: 2px;
    flex-shrink: 0;
  }
  .legend-count {
    font-weight: 700;
    color: #e2e8f0;
  }

  /* Stat cards strip */
  .stat-strip {
    display: flex;
    flex-direction: column;
    gap: 8px;
    flex-shrink: 0;
    min-width: 130px;
  }
  .stat-card {
    background: #16213e;
    border: 1px solid #334155;
    border-radius: 8px;
    padding: 10px 14px;
    text-align: center;
    flex: 1;
  }
  .stat-card.alert {
    border-color: rgba(220, 38, 38, 0.4);
    background: rgba(220, 38, 38, 0.06);
  }
  .stat-num {
    font-size: 22px;
    font-weight: 700;
    color: #fff;
    line-height: 1.2;
  }
  .stat-card.alert .stat-num { color: #fca5a5; }
  .stat-desc {
    font-size: 10px;
    color: #94a3b8;
    text-transform: uppercase;
    letter-spacing: 0.3px;
    margin-top: 1px;
  }

  /* ---- P0 Blocker Callout ---- */
  .blocker-callout {
    margin: 0 32px 8px;
    background: rgba(220, 38, 38, 0.08);
    border: 1px solid rgba(220, 38, 38, 0.3);
    border-radius: 8px;
    padding: 12px 16px;
  }
  .blocker-header {
    font-size: 11px;
    font-weight: 700;
    color: #f87171;
    text-transform: uppercase;
    letter-spacing: 1px;
    margin-bottom: 8px;
  }
  .blocker-list {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .blocker-item {
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 12px;
  }
  .blocker-status {
    font-size: 10px;
    color: #fca5a5;
    background: rgba(220, 38, 38, 0.15);
    padding: 1px 6px;
    border-radius: 3px;
    text-transform: uppercase;
    font-weight: 600;
    white-space: nowrap;
  }
  .blocker-title { color: #e2e8f0; flex: 1; }
  .blocker-assignee { font-size: 10px; color: #94a3b8; white-space: nowrap; }

  /* ---- Pipeline ---- */
  .pipeline {
    padding: 8px 32px 4px;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }
  .pipe-stage {
    display: flex;
    align-items: center;
    gap: 8px;
    height: 22px;
  }
  .pipe-bar {
    height: 14px;
    border-radius: 3px;
    min-width: 8px;
    transition: width 0.3s ease;
  }
  .pipe-info {
    font-size: 11px;
    color: #94a3b8;
    white-space: nowrap;
  }
  .pipe-count {
    font-weight: 700;
    color: #e2e8f0;
  }

  .divider {
    height: 1px;
    margin: 16px 32px;
    background: linear-gradient(90deg, transparent, #334155, transparent);
  }

  /* ---- Section Headers ---- */
  .section-header {
    padding: 8px 32px 4px;
    font-size: 13px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.8px;
    color: #64748b;
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .section-header .section-count {
    background: #334155;
    color: #94a3b8;
    font-size: 11px;
    padding: 1px 8px;
    border-radius: 10px;
    font-weight: 500;
  }

  /* ---- Board ---- */
  .board {
    display: flex;
    gap: 12px;
    padding: 8px 32px 16px;
    overflow-x: auto;
    align-items: flex-start;
  }
  .column {
    min-width: 220px;
    max-width: 280px;
    flex: 1 0 220px;
    background: #16213e;
    border-radius: 8px;
    display: flex;
    flex-direction: column;
    max-height: 60vh;
  }
  .col-header {
    padding: 10px 12px;
    border-top: 3px solid #6b7280;
    display: flex;
    justify-content: space-between;
    align-items: center;
    border-radius: 8px 8px 0 0;
    flex-shrink: 0;
  }
  .col-label {
    font-weight: 600;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: #cbd5e1;
  }
  .col-count {
    background: #334155;
    color: #94a3b8;
    font-size: 11px;
    padding: 1px 7px;
    border-radius: 10px;
    font-weight: 500;
  }
  .col-body {
    padding: 6px 8px 8px;
    overflow-y: auto;
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  /* ---- Cards ---- */
  .card {
    background: #1a1a2e;
    border: 1px solid #334155;
    border-radius: 6px;
    padding: 10px 12px;
    cursor: default;
    transition: border-color 0.15s ease, transform 0.1s ease, box-shadow 0.15s ease;
  }
  .card:hover {
    border-color: #60a5fa;
    transform: translateY(-1px);
    box-shadow: 0 2px 8px rgba(0,0,0,0.3);
  }
  .card-title {
    font-size: 13px;
    font-weight: 500;
    line-height: 1.35;
    margin-bottom: 3px;
    color: #e2e8f0;
  }
  .card-id {
    font-size: 11px;
    color: #64748b;
    font-family: 'SF Mono', 'Fira Code', Menlo, Consolas, monospace;
  }
  .pri {
    display: inline-block;
    font-size: 10px;
    font-weight: 700;
    color: #fff;
    padding: 1px 6px;
    border-radius: 3px;
    margin-bottom: 4px;
    margin-right: 4px;
    vertical-align: middle;
  }
  .spec-badge {
    display: inline-block;
    font-size: 10px;
    font-weight: 600;
    color: #3b82f6;
    background: rgba(59, 130, 246, 0.15);
    padding: 1px 6px;
    border-radius: 3px;
    margin-bottom: 4px;
    margin-right: 4px;
    vertical-align: middle;
  }
  .assignee {
    font-size: 11px;
    color: #94a3b8;
    margin-top: 5px;
  }
  .notes {
    font-size: 11px;
    color: #64748b;
    margin-top: 4px;
    font-style: italic;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
    line-height: 1.4;
  }
  .completed {
    font-size: 10px;
    color: #22c55e;
    margin-top: 4px;
    font-weight: 500;
  }

  /* ---- Recent Wins ---- */
  .wins-section {
    padding: 8px 32px 24px;
  }
  .wins-grid {
    display: flex;
    gap: 8px;
    overflow-x: auto;
    padding: 4px 0;
  }
  .wins-grid .card {
    min-width: 200px;
    max-width: 260px;
    flex: 0 0 auto;
    border-left: 3px solid #22c55e;
  }

  /* ---- Empty State ---- */
  .col-empty {
    font-size: 11px;
    color: #475569;
    text-align: center;
    padding: 16px 8px;
    font-style: italic;
  }

  /* ---- Responsive ---- */
  @media (max-width: 900px) {
    .hero { padding: 12px 16px; flex-direction: column; gap: 12px; }
    .stat-strip { flex-direction: row; min-width: 0; }
    .stat-card { min-width: 80px; padding: 8px 10px; }
    .stat-num { font-size: 18px; }
    .header-bar { padding: 8px 12px; }
    .session-panel { margin: 12px 16px 0; padding: 10px 12px; }
    .section-header, .wins-section, .pipeline, .blocker-callout { padding-left: 16px; padding-right: 16px; margin-left: 0; margin-right: 0; }
    .board { padding: 8px 16px 16px; flex-direction: column; }
    .column { min-width: 100%; max-width: 100%; max-height: none; }
    .divider { margin: 16px; }
  }
</style>
</head>
<body>

<!-- ======== HEADER ======== -->
<div class="header-bar">
  <h1>${esc(projectName)} Dashboard</h1>
  <div class="global-filters">
    <select id="statusFilter">
      <option value="">All Statuses</option>
    </select>
    <select id="priFilter">
      <option value="">All Priorities</option>
    </select>
    <input id="search" type="text" placeholder="Search tickets...">
  </div>
  <span class="header-status"><span class="live-dot"></span>${esc(now)}</span>
</div>

<div id="sessionPanel"></div>
<div id="hero"></div>
<div id="blockers"></div>
<div id="pipeline"></div>
<div class="divider"></div>
<div id="boardSection"></div>
<div class="divider"></div>
<div id="winsSection"></div>

<script>
var ALL_TICKETS = ${ticketData};
var COLUMNS = ${columnsJson};
var PRI_COLORS = ${priColorsJson};
var SESSION = ${sessionJson};
var TODAY = new Date();
var WEEK_AGO = new Date(TODAY); WEEK_AGO.setDate(WEEK_AGO.getDate() - 7);

// Priority sort order
function priOrd(p) { return { P0:0, P1:1, P2:2, P3:3, P5:5 }[p] || 9; }

// Escape HTML
function esc(s) {
  if (!s) return '';
  return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// Populate filter dropdowns from data
(function() {
  var sf = document.getElementById('statusFilter');
  COLUMNS.forEach(function(c) {
    var o = document.createElement('option');
    o.value = c.id;
    o.textContent = c.label;
    sf.appendChild(o);
  });
  var pf = document.getElementById('priFilter');
  var pris = {};
  ALL_TICKETS.forEach(function(t) { if (t.p) pris[t.p] = 1; });
  Object.keys(pris).sort(function(a,b) { return priOrd(a) - priOrd(b); }).forEach(function(p) {
    var o = document.createElement('option');
    o.value = p;
    o.textContent = p;
    pf.appendChild(o);
  });
})();

// Check if ticket matches current filters
function matchesFilters(t) {
  var stat = document.getElementById('statusFilter').value;
  var pri = document.getElementById('priFilter').value;
  var q = document.getElementById('search').value.toLowerCase().trim();
  var matchStat = !stat || t.s === stat;
  var matchPri = !pri || t.p === pri;
  var matchQ = !q || t.t.toLowerCase().indexOf(q) !== -1 || t.n.toLowerCase().indexOf(q) !== -1
    || (t.no && t.no.toLowerCase().indexOf(q) !== -1)
    || (t.a && t.a.toLowerCase().indexOf(q) !== -1);
  return matchStat && matchPri && matchQ;
}

// Build a card HTML
function cardHtml(t, opts) {
  opts = opts || {};
  var inner = '';
  if (t.p) inner += '<span class="pri" style="background:' + (PRI_COLORS[t.p]||'#6b7280') + '">' + esc(t.p) + '</span>';
  if (t.sp) inner += '<span class="spec-badge">Spec</span>';
  inner += '<div class="card-title">' + esc(t.t) + '</div>';
  inner += '<div class="card-id">' + esc(t.n) + '</div>';
  if (t.a && t.a !== '-' && t.a.toLowerCase() !== 'unassigned') inner += '<div class="assignee">' + esc(t.a) + '</div>';
  if (t.no) inner += '<div class="notes" title="' + esc(t.no) + '">' + esc(t.no.substring(0,120)) + (t.no.length>120?'...':'') + '</div>';
  if (opts.showCompleted && t.c) inner += '<div class="completed">Done: ' + esc(t.c.split(' ')[0]) + '</div>';
  return '<div class="card" title="' + esc(t.n) + '">' + inner + '</div>';
}

// Build kanban columns for a set of tickets
function columnsHtml(tickets) {
  var grouped = {};
  COLUMNS.forEach(function(c) { grouped[c.id] = []; });
  tickets.forEach(function(t) {
    if (grouped[t.s]) grouped[t.s].push(t);
    else if (grouped['BACKLOG']) grouped['BACKLOG'].push(t);
  });
  Object.keys(grouped).forEach(function(k) {
    grouped[k].sort(function(a,b) { return priOrd(a.p) - priOrd(b.p); });
  });
  return COLUMNS.map(function(col) {
    var items = grouped[col.id];
    var cards = items.map(function(t) { return cardHtml(t); }).join('');
    if (!cards) cards = '<div class="col-empty">Clear</div>';
    return '<div class="column"><div class="col-header" style="border-top-color:' + col.color + '">'
      + '<span class="col-label">' + col.label + '</span><span class="col-count">' + items.length + '</span></div>'
      + '<div class="col-body">' + cards + '</div></div>';
  }).join('');
}

// Full render
function render() {
  var active = ALL_TICKETS.filter(function(t) { return t.s !== 'CLOSED'; });
  var closed = ALL_TICKETS.filter(function(t) { return t.s === 'CLOSED'; });
  var filtered = active.filter(matchesFilters);

  // Session state panel
  if (SESSION) {
    var sp = '<div class="session-panel">';
    if (SESSION.version) sp += '<div class="session-item"><span class="session-label">Version</span><span class="session-value">' + esc(SESSION.version) + '</span></div>';
    if (SESSION.branch) sp += '<div class="session-item"><span class="session-label">Branch</span><span class="session-value">' + esc(SESSION.branch) + '</span></div>';
    if (SESSION.tests) {
      var cls = SESSION.tests.toLowerCase().indexOf('pass') !== -1 ? 'ok' : 'warn';
      sp += '<div class="session-item"><span class="session-label">Tests</span><span class="session-value ' + cls + '">' + esc(SESSION.tests) + '</span></div>';
    }
    if (SESSION.lastUpdated) sp += '<div class="session-item"><span class="session-label">Updated</span><span class="session-value">' + esc(SESSION.lastUpdated) + '</span></div>';
    sp += '</div>';
    document.getElementById('sessionPanel').innerHTML = sp;
  }

  // Status counts
  var counts = {};
  COLUMNS.forEach(function(c) { counts[c.id] = 0; });
  filtered.forEach(function(t) {
    if (counts[t.s] !== undefined) counts[t.s]++;
    else if (counts['BACKLOG'] !== undefined) counts['BACKLOG']++;
  });

  var totalFiltered = filtered.length;
  var p0s = filtered.filter(function(t) { return t.p === 'P0'; });

  // Status bar segments
  var statusSegs = COLUMNS.map(function(c) {
    return { count: counts[c.id], color: c.color, label: c.label };
  });
  var barTotal = Math.max(1, totalFiltered);
  var barSegsHtml = statusSegs.map(function(s) {
    if (s.count === 0) return '';
    var w = (s.count / barTotal * 100);
    return '<div class="status-bar-seg" style="width:' + w.toFixed(1) + '%;background:' + s.color + '" title="' + s.label + ': ' + s.count + '"></div>';
  }).join('');
  var legendHtml = statusSegs.map(function(s) {
    return '<div class="legend-item"><span class="legend-dot" style="background:' + s.color + '"></span><span class="legend-count">' + s.count + '</span> ' + s.label + '</div>';
  }).join('');

  // Velocity
  var closedThisWeek = closed.filter(function(t) {
    if (!t.c) return false;
    return new Date(t.c.replace(/\\s+/, 'T')) >= WEEK_AGO;
  }).length;

  var needsHuman = counts['NEEDS_HUMAN'] || 0;
  var inReview = counts['IN_REVIEW'] || 0;

  // Hero
  var heroHtml = '<div class="hero">'
    + '<div class="status-bar-section">'
    + '<div class="status-bar-header"><span class="status-bar-title">Status Breakdown</span>'
    + '<span class="status-bar-total">' + totalFiltered + '<small>active</small></span></div>'
    + '<div class="status-bar-wrap">' + barSegsHtml + '</div>'
    + '<div class="status-bar-legend">' + legendHtml + '</div>'
    + '</div>'
    + '<div class="stat-strip">'
    + '<div class="stat-card"><div class="stat-num">' + closedThisWeek + '</div><div class="stat-desc">Closed this week</div></div>'
    + '<div class="stat-card"><div class="stat-num">' + inReview + '</div><div class="stat-desc">In review</div></div>'
    + (needsHuman > 0 ? '<div class="stat-card"><div class="stat-num">' + needsHuman + '</div><div class="stat-desc">Needs human</div></div>' : '')
    + (p0s.length > 0 ? '<div class="stat-card alert"><div class="stat-num">' + p0s.length + '</div><div class="stat-desc">P0 blockers</div></div>' : '')
    + '</div>'
    + '</div>';
  document.getElementById('hero').innerHTML = heroHtml;

  // Blockers
  if (p0s.length > 0) {
    var bl = '<div class="blocker-callout"><div class="blocker-header">P0 BLOCKERS</div><div class="blocker-list">';
    p0s.forEach(function(t) {
      bl += '<div class="blocker-item"><span class="blocker-status">' + esc(t.s.replace(/_/g,' ')) + '</span>'
        + '<span class="blocker-title">' + esc(t.t) + '</span>'
        + (t.a ? '<span class="blocker-assignee">' + esc(t.a) + '</span>' : '')
        + '</div>';
    });
    bl += '</div></div>';
    document.getElementById('blockers').innerHTML = bl;
  } else {
    document.getElementById('blockers').innerHTML = '';
  }

  // Pipeline
  var stages = COLUMNS.slice();
  var stageCounts = stages.map(function(s) {
    return { label: s.label, color: s.color, count: filtered.filter(function(t) { return t.s === s.id; }).length };
  });
  var pipeMax = Math.max(1, Math.max.apply(null, stageCounts.map(function(s) { return s.count; })));
  var pipeHtml = '<div class="section-header">Pipeline</div><div class="pipeline">';
  stageCounts.forEach(function(s) {
    var pct = Math.max(8, (s.count / pipeMax) * 100);
    pipeHtml += '<div class="pipe-stage"><div class="pipe-bar" style="width:' + pct + '%;background:' + s.color + '"></div>'
      + '<div class="pipe-info"><span class="pipe-count">' + s.count + '</span> ' + s.label + '</div></div>';
  });
  pipeHtml += '</div>';
  document.getElementById('pipeline').innerHTML = pipeHtml;

  // Board
  var boardHtml = '<div class="section-header">Kanban Board <span class="section-count">' + filtered.length + '</span></div>'
    + '<div class="board">' + columnsHtml(filtered) + '</div>';
  document.getElementById('boardSection').innerHTML = boardHtml;

  // Recent Wins (last 12 closed with dates, most recent first)
  var wins = closed.filter(function(t) { return t.c; })
    .sort(function(a,b) { return new Date(b.c.replace(/\\s+/,'T')) - new Date(a.c.replace(/\\s+/,'T')); })
    .slice(0, 12);
  var winsHtml = '<div class="section-header">Recent Wins <span class="section-count">' + wins.length + '</span></div>'
    + '<div class="wins-section"><div class="wins-grid">';
  if (wins.length) {
    wins.forEach(function(t) { winsHtml += cardHtml(t, { showCompleted: true }); });
  } else {
    winsHtml += '<div class="col-empty">No completed tickets with dates yet.</div>';
  }
  winsHtml += '</div></div>';
  document.getElementById('winsSection').innerHTML = winsHtml;
}

// Event handlers
document.getElementById('statusFilter').addEventListener('change', render);
document.getElementById('priFilter').addEventListener('change', render);
document.getElementById('search').addEventListener('input', render);

// Initial render
render();
</script>
</body>
</html>`;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

var tickets = loadTickets();
var html = buildPage(tickets);
fs.writeFileSync(OUTPUT, html);
console.log('Dashboard written to ' + OUTPUT + ' (' + tickets.length + ' tickets)');

if (!SERVE) {
  try { execSync('open ' + OUTPUT); } catch (e) { /* not macOS */ }
}

if (SERVE) {
  var server = http.createServer(function(req, res) {
    if (req.url === '/' || req.url === '/index.html' || req.url === '/dashboard.html') {
      var fresh = buildPage(loadTickets());
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(fresh);
    } else {
      res.writeHead(404);
      res.end('Not found');
    }
  });
  server.listen(PORT, function() {
    console.log('Serving live at http://localhost:' + PORT);
    try { execSync('open http://localhost:' + PORT); } catch (e) { /* not macOS */ }
  });
}
