#!/usr/bin/env node
// build-codex.js — Pre-indexes codebase structure into compact markdown files
// so Claude skips 10-20 exploration tool calls per conversation.
// Zero external dependencies (Node.js built-ins only). Runs in <1s.
// Output: .ai-codex/*.md
//
// Config: reads codex-config.json at project root, falls back to
// harness-config.json "codex" section, then sensible defaults.

const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const ROOT = findProjectRoot();
const OUT = path.join(ROOT, '.ai-codex');
const NOW = new Date().toISOString().slice(0, 10);

const DEFAULTS = {
  endpointDirs: ['api/'],
  sharedDirs: ['lib/', 'api/shared/'],
  pageDirs: ['public/'],
  componentDirs: ['public/js/', 'src/components/'],
  extensions: ['.js', '.ts', '.jsx', '.tsx'],
  endpointCategories: {},
  infraScripts: [],
  ignoredDirs: ['node_modules', '.git', 'dist', 'build', '__mocks__', '.ai-codex'],
};

const CONFIG = loadConfig();

// Ensure output dir
if (!fs.existsSync(OUT)) fs.mkdirSync(OUT, { recursive: true });

// Find project root by walking up from cwd looking for package.json or .git
function findProjectRoot() {
  let dir = process.cwd();
  while (dir !== path.dirname(dir)) {
    if (fs.existsSync(path.join(dir, 'package.json')) || fs.existsSync(path.join(dir, '.git'))) {
      return dir;
    }
    dir = path.dirname(dir);
  }
  return process.cwd();
}

// Load config from codex-config.json or harness-config.json
function loadConfig() {
  const codexPath = path.join(ROOT, 'codex-config.json');
  const harnessPath = path.join(ROOT, 'harness-config.json');

  let raw = {};
  if (fs.existsSync(codexPath)) {
    try { raw = JSON.parse(fs.readFileSync(codexPath, 'utf8')); } catch {}
  } else if (fs.existsSync(harnessPath)) {
    try { raw = JSON.parse(fs.readFileSync(harnessPath, 'utf8')).codex || {}; } catch {}
  }

  return { ...DEFAULTS, ...raw };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Read file safely
function read(filePath) {
  try { return fs.readFileSync(filePath, 'utf8'); } catch { return ''; }
}

// List files matching configured extensions in a directory (non-recursive)
function listFiles(dir) {
  try {
    return fs.readdirSync(dir)
      .filter(f => CONFIG.extensions.some(ext => f.endsWith(ext)))
      .sort();
  } catch { return []; }
}

// List files matching a specific extension
function filesWithExt(dir, ext) {
  try {
    return fs.readdirSync(dir)
      .filter(f => f.endsWith(ext))
      .sort();
  } catch { return []; }
}

// Recursively walk a directory, returning relative paths
function walkDir(dir, relBase) {
  const results = [];
  if (!fs.existsSync(dir)) return results;

  const base = relBase || '';
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return results; }

  for (const entry of entries) {
    if (CONFIG.ignoredDirs.includes(entry.name)) continue;
    const fullPath = path.join(dir, entry.name);
    const relPath = base ? `${base}/${entry.name}` : entry.name;

    if (entry.isDirectory()) {
      results.push(...walkDir(fullPath, relPath));
    } else if (CONFIG.extensions.some(ext => entry.name.endsWith(ext))) {
      results.push({ fullPath, relPath, name: entry.name });
    }
  }
  return results;
}

// List subdirectories of a directory
function listSubdirs(dir) {
  try {
    return fs.readdirSync(dir, { withFileTypes: true })
      .filter(d => d.isDirectory() && !CONFIG.ignoredDirs.includes(d.name))
      .map(d => d.name)
      .sort();
  } catch { return []; }
}

// ---------------------------------------------------------------------------
// Extraction functions
// ---------------------------------------------------------------------------

// Extract one-line description from first meaningful comment or JSDoc
function extractDescription(content) {
  const lines = content.split('\n').slice(0, 30);

  // Try JSDoc @description or @fileoverview first
  for (const line of lines) {
    const jsdoc = line.match(/@(?:description|fileoverview|summary)\s+(.{10,120})/);
    if (jsdoc) return jsdoc[1].trim().replace(/\*\/$/, '').trim();
  }

  // Try first line of a /** ... */ block (skip the opening /**)
  let inJsdoc = false;
  for (const line of lines) {
    if (/^\s*\/\*\*/.test(line)) { inJsdoc = true; continue; }
    if (inJsdoc) {
      const m = line.match(/^\s*\*\s+([A-Z].{10,120})/);
      if (m && !m[1].includes('@')) return m[1].trim().replace(/\*\/$/, '').trim();
      if (/\*\//.test(line)) inJsdoc = false;
    }
  }

  // Fallback: standalone // comment
  for (const line of lines) {
    const m = line.match(/^\/\/\s+([A-Z].{10,80})$/);
    if (m && !m[1].includes('require') && !m[1].includes('eslint') && !m[1].includes('TODO')) {
      return m[1].trim();
    }
  }
  return '';
}

// Detect HTTP methods from endpoint code
function detectMethods(content) {
  const methods = new Set();

  // req.method === 'METHOD'
  for (const method of ['GET', 'POST', 'PUT', 'DELETE', 'PATCH']) {
    if (new RegExp(`req\\.method\\s*===?\\s*['"]${method}`, 'i').test(content)) methods.add(method);
    if (new RegExp(`case\\s+['"]${method}['"]\\s*:`, 'i').test(content)) methods.add(method);
  }

  // Negated pattern: req.method !== 'POST' means it only accepts POST
  const negatedMatch = content.match(/req\.method\s*!==?\s*['"](\w+)['"]/);
  if (negatedMatch && methods.size === 0) {
    methods.add(negatedMatch[1].toUpperCase());
  }

  // event.httpMethod pattern (Vercel/Lambda)
  const httpMethodEq = content.match(/(?:event|req)\.httpMethod\s*===?\s*['"](\w+)['"]/);
  if (httpMethodEq) methods.add(httpMethodEq[1].toUpperCase());
  const httpMethodNeq = content.match(/(?:event|req)\.httpMethod\s*!==?\s*['"](\w+)['"]/);
  if (httpMethodNeq && methods.size === 0) methods.add(httpMethodNeq[1].toUpperCase());

  // Express-style: router.get(), app.post(), etc.
  for (const method of ['get', 'post', 'put', 'delete', 'patch']) {
    if (new RegExp(`(?:router|app)\\.${method}\\s*\\(`).test(content)) methods.add(method.toUpperCase());
  }

  // Fallback: check for body reads (implies POST)
  if (methods.size === 0) {
    if (/req\.body/i.test(content)) methods.add('POST');
    else methods.add('GET');
  }
  return [...methods].sort();
}

// Detect if a file is an HTTP endpoint (has req/res handler pattern)
function isEndpoint(content) {
  // Standard handler: function(req, res) or (req, res) =>
  if (/(?:function\s+\w+|module\.exports\s*=\s*(?:\w+\s*\()?\s*(?:async\s+)?function)\s*\([^)]*req\s*,\s*res/.test(content)) return true;
  if (/\(\s*req\s*,\s*res\s*\)\s*=>/.test(content)) return true;
  // Wrapper patterns: withSomething(async (req, res) => ...)
  if (/\w+\s*\(\s*(?:async\s+)?(?:function)?\s*\(\s*req\s*,\s*res/.test(content)) return true;
  // Express router: router.get/post/etc
  if (/(?:router|app)\.\s*(?:get|post|put|delete|patch|all|use)\s*\(/.test(content)) return true;
  return false;
}

// Detect auth type from common patterns
function detectAuth(content) {
  if (/requireAdmin|isAdmin/.test(content)) return 'admin';
  if (/requireAuth|isAuthenticated|ensureAuth/.test(content)) return 'auth';
  if (/extractToken|verifyToken|jwt\.verify|Bearer/.test(content)) return 'token';
  return 'public';
}

// Extract exports from a module (brace-balanced module.exports)
function extractExports(content) {
  const exports = [];

  // module.exports = { ... } with brace balancing
  const startMatch = content.match(/module\.exports\s*=\s*\{/);
  if (startMatch) {
    const startIdx = startMatch.index + startMatch[0].length;
    let depth = 1;
    let endIdx = startIdx;
    for (let i = startIdx; i < content.length && depth > 0; i++) {
      if (content[i] === '{') depth++;
      else if (content[i] === '}') depth--;
      endIdx = i;
    }
    const inner = content.slice(startIdx, endIdx);

    // Extract top-level keys
    const keyRegex = /(?:^|[\n,])\s*(\w+)\s*(?:[:,]|\s*\()/gm;
    let km;
    const keywords = new Set(['function', 'async', 'const', 'let', 'var', 'return', 'if', 'else',
      'true', 'false', 'null', 'undefined', 'new', 'this', 'class', 'switch', 'case',
      'break', 'default', 'try', 'catch', 'throw', 'typeof', 'instanceof']);
    while ((km = keyRegex.exec(inner)) !== null) {
      const name = km[1];
      if (name.length > 1 && !keywords.has(name)) exports.push(name);
    }
  }

  // module.exports = functionName
  if (exports.length === 0) {
    const singleMatch = content.match(/module\.exports\s*=\s*(?:\w+\s*\(\s*)?(?:async\s+)?function\s+(\w+)/);
    if (singleMatch) exports.push(singleMatch[1]);
  }

  // exports.name = ... or export { name }
  const namedExports = content.matchAll(/exports\.(\w+)\s*=/g);
  for (const m of namedExports) {
    if (!exports.includes(m[1])) exports.push(m[1]);
  }

  // ES module: export function/const
  const esExports = content.matchAll(/export\s+(?:async\s+)?(?:function|const|let|class)\s+(\w+)/g);
  for (const m of esExports) {
    if (!exports.includes(m[1])) exports.push(m[1]);
  }

  // export default
  const defaultExport = content.match(/export\s+default\s+(?:async\s+)?(?:function\s+)?(\w+)/);
  if (defaultExport && !exports.includes(defaultExport[1]) && defaultExport[1] !== 'function') {
    exports.push(defaultExport[1]);
  }

  return [...new Set(exports)];
}

// Extract function signatures (name + params)
function extractFunctions(content) {
  const fns = [];
  // function name(params)
  const funcMatches = content.matchAll(/(?:async\s+)?function\s+(\w+)\s*\(([^)]*)\)/g);
  for (const m of funcMatches) {
    fns.push({ name: m[1], params: m[2].trim() });
  }
  // const name = async (params) =>
  const arrowMatches = content.matchAll(/(?:const|let)\s+(\w+)\s*=\s*(?:async\s+)?\(([^)]*)\)\s*=>/g);
  for (const m of arrowMatches) {
    if (!fns.find(f => f.name === m[1])) {
      fns.push({ name: m[1], params: m[2].trim() });
    }
  }
  return fns;
}

// Detect frontend JS pattern (IIFE, global, page controller, class)
function detectJsPattern(content) {
  if (/^\s*\(function\s*\(\)\s*\{/m.test(content) || /^\s*\(\(\)\s*=>\s*\{/m.test(content)) {
    return 'IIFE (self-init)';
  }

  const globalExclude = /^(addEventListener|location|history|document|navigator|setTimeout|setInterval|clearTimeout|clearInterval|requestAnimationFrame|onload|onerror|fetch|scroll|open|close|print|alert|confirm|prompt|performance)$/;
  const globalMatches = content.matchAll(/window\.(\w+)\s*=/g);
  for (const m of globalMatches) {
    if (!globalExclude.test(m[1])) return `global -> window.${m[1]}`;
  }

  if (/document\.addEventListener\s*\(\s*['"]DOMContentLoaded/.test(content) ||
      /window\.addEventListener\s*\(\s*['"](?:load|DOMContentLoaded)['"]/.test(content)) {
    return 'page controller';
  }

  if (/class\s+\w+/.test(content)) {
    const m = content.match(/class\s+(\w+)/);
    return `class -> ${m[1]}`;
  }

  // React component detection
  if (/export\s+(?:default\s+)?function\s+\w+.*?return\s*\(?\s*</.test(content) ||
      /React\.createElement/.test(content)) {
    return 'React component';
  }

  return 'script';
}

// Extract which API endpoints a frontend JS file calls
function extractApiCalls(content) {
  const apis = new Set();
  const matches = content.matchAll(/['"`]\/api\/([\w\-/]+)/g);
  for (const m of matches) apis.add(`/api/${m[1]}`);
  return [...apis].sort();
}

// Extract JS src files from HTML
function extractScriptSrcs(content) {
  const srcs = [];
  const matches = content.matchAll(/src=["']([^"']+\.(?:js|ts|jsx|tsx))["']/g);
  for (const m of matches) srcs.push(m[1].replace(/^\.?\//, ''));
  return srcs;
}

// Extract CSS links from HTML
function extractCssLinks(content) {
  const links = [];
  const matches = content.matchAll(/href=["']([^"']+\.css)["']/g);
  for (const m of matches) links.push(m[1].replace(/^\.?\//, ''));
  return links;
}

// Detect if HTML page requires auth (generic: looks for auth-related script names)
function detectPageAuth(content) {
  if (/auth[_-]guard/i.test(content) || /requireAuth/i.test(content)) return 'authenticated';
  if (/public[_-]header/i.test(content) || /no[_-]?auth/i.test(content)) return 'public';
  // Check meta tags
  if (/meta\s+name=["']auth["']\s+content=["']required["']/i.test(content)) return 'authenticated';
  return 'unknown';
}

// Extract Firestore collection paths from code
function extractFirestorePaths(content) {
  const paths = new Set();

  // .collection('name')
  const collMatches = content.matchAll(/\.collection\s*\(\s*['"]([^'"]+)['"]\s*\)/g);
  for (const m of collMatches) paths.add(m[1]);

  // Variable: const X_COLLECTION = 'name'
  const constMatches = content.matchAll(/(?:const|let|var)\s+\w*(?:COLLECTION|collection)\w*\s*=\s*['"]([^'"]+)['"]/g);
  for (const m of constMatches) paths.add(m[1]);

  // COLLECTIONS object: { KEY: 'value' }
  const collectionsBlock = content.match(/COLLECTIONS\s*=\s*\{([^}]+)\}/s);
  if (collectionsBlock) {
    const valMatches = collectionsBlock[1].matchAll(/:\s*['"]([^'"]+)['"]/g);
    for (const m of valMatches) paths.add(m[1]);
  }

  return [...paths].sort();
}

// ---------------------------------------------------------------------------
// Categorization (config-driven)
// ---------------------------------------------------------------------------

// Build categorizer from config.endpointCategories
function buildCategorizer() {
  const rules = [];
  for (const [pattern, label] of Object.entries(CONFIG.endpointCategories)) {
    rules.push({ regex: new RegExp(pattern), label });
  }
  return function categorize(filename) {
    for (const rule of rules) {
      if (rule.regex.test(filename)) return rule.label;
    }
    return 'Other';
  };
}

// ---------------------------------------------------------------------------
// 1. ENDPOINTS
// ---------------------------------------------------------------------------
function buildEndpoints() {
  const lines = [`# API Endpoints (generated ${NOW})`, '', ''];
  const categorize = buildCategorizer();
  const categories = new Map();
  let total = 0;

  // Resolve infra scripts set for filtering
  const infraSet = new Set(CONFIG.infraScripts.map(s => s.replace(/^\.?\//, '')));

  for (const dirRel of CONFIG.endpointDirs) {
    const dir = path.join(ROOT, dirRel);
    const files = walkDir(dir, dirRel.replace(/\/$/, ''));

    for (const { fullPath, relPath, name } of files) {
      const content = read(fullPath);
      if (!isEndpoint(content)) continue;

      const methods = detectMethods(content);
      const auth = detectAuth(content);
      const desc = extractDescription(content);
      const cat = categorize(name);

      // Build route path from relative path (strip extension)
      const routePath = '/' + relPath.replace(/\.[^.]+$/, '');

      const flags = [];
      flags.push(auth.toUpperCase()[0]); // A=auth, T=token, P=public, D=admin
      if (/checkRateLimit|rateLimit/i.test(content)) flags.push('RL');

      if (!categories.has(cat)) categories.set(cat, []);
      categories.get(cat).push(
        `| \`${routePath}\` | ${methods.join(',')} | ${auth} | [${flags.join(',')}] | ${desc} |`
      );
      total++;
    }
  }

  lines.splice(2, 0, `**${total} endpoints** -- Flags: A=auth, T=token, P=public, D=admin, RL=rate-limited`);
  lines.splice(3, 0, '');

  for (const [cat, rows] of categories.entries()) {
    if (rows.length === 0) continue;
    lines.push(`## ${cat} (${rows.length})`);
    lines.push('| Endpoint | Methods | Auth | Flags | Description |');
    lines.push('|----------|---------|------|-------|-------------|');
    lines.push(...rows);
    lines.push('');
  }

  fs.writeFileSync(path.join(OUT, 'endpoints.md'), lines.join('\n'));
  return total;
}

// ---------------------------------------------------------------------------
// 2. SHARED MODULES
// ---------------------------------------------------------------------------
function buildShared() {
  const lines = [`# Shared Modules (generated ${NOW})`, ''];
  let totalModules = 0;

  // Render a single module line
  function renderModule(fullPath, name) {
    const content = read(fullPath);
    const exports = extractExports(content);
    const fns = extractFunctions(content);

    const exportLine = exports.map(exp => {
      const fn = fns.find(f => f.name === exp);
      return fn ? `${exp}(${fn.params})` : exp;
    }).join(', ');

    if (exportLine) {
      return `- **${name}** -> \`${exportLine}\``;
    }
    const desc = extractDescription(content);
    return `- **${name}**${desc ? ' -- ' + desc : ''}`;
  }

  for (const dirRel of CONFIG.sharedDirs) {
    const dir = path.join(ROOT, dirRel);
    if (!fs.existsSync(dir)) continue;

    const label = dirRel.replace(/\/$/, '');

    // Check for subdirectories to create sub-sections
    const subdirs = listSubdirs(dir);
    const topFiles = listFiles(dir).filter(f => {
      // In endpoint dirs, skip files that are endpoints (they belong in endpoints.md)
      const content = read(path.join(dir, f));
      return !isEndpoint(content);
    });

    if (topFiles.length > 0) {
      totalModules += topFiles.length;
      lines.push(`## ${label}/ (${topFiles.length})`);
      lines.push('');
      for (const file of topFiles) {
        lines.push(renderModule(path.join(dir, file), file));
      }
      lines.push('');
    }

    // Recurse into subdirectories
    for (const sub of subdirs) {
      if (CONFIG.ignoredDirs.includes(sub)) continue;
      const subDir = path.join(dir, sub);
      const subFiles = listFiles(subDir);
      if (subFiles.length === 0) continue;

      totalModules += subFiles.length;
      lines.push(`## ${label}/${sub}/ (${subFiles.length})`);
      lines.push('');
      for (const file of subFiles) {
        lines.push(renderModule(path.join(subDir, file), file));
      }
      lines.push('');
    }
  }

  // Insert total at top
  lines.splice(1, 0, '', `**${totalModules} total modules**`, '');

  fs.writeFileSync(path.join(OUT, 'shared.md'), lines.join('\n'));
  return totalModules;
}

// ---------------------------------------------------------------------------
// 3. PAGES
// ---------------------------------------------------------------------------
function buildPages() {
  const lines = [`# Pages (generated ${NOW})`, ''];
  let totalPages = 0;

  // Build infra scripts set from config
  const infraSet = new Set(CONFIG.infraScripts.map(s => s.replace(/^\.?\//, '')));

  const authPages = [];
  const publicPages = [];
  const unknownPages = [];

  for (const dirRel of CONFIG.pageDirs) {
    const dir = path.join(ROOT, dirRel);
    if (!fs.existsSync(dir)) continue;

    const htmlFiles = filesWithExt(dir, '.html');
    for (const file of htmlFiles) {
      const content = read(path.join(dir, file));
      const auth = detectPageAuth(content);
      const scripts = extractScriptSrcs(content);
      const css = extractCssLinks(content);

      // Filter out infrastructure scripts
      const pageScripts = scripts.filter(s => !infraSet.has(s));

      const relFile = dirRel === '' ? file : `${dirRel.replace(/\/$/, '')}/${file}`;
      const scriptCol = pageScripts.length > 0 ? pageScripts.map(s => `\`${s}\``).join(', ') : '--';
      const cssCol = css.length > 0 ? css.map(s => `\`${s}\``).join(', ') : '';

      const entry = `| \`${relFile}\` | ${auth} | ${scriptCol} |`;
      totalPages++;

      if (auth === 'authenticated') authPages.push(entry);
      else if (auth === 'public') publicPages.push(entry);
      else unknownPages.push(entry);
    }

    // Also check subdirectories for HTML files
    for (const sub of listSubdirs(dir)) {
      const subHtml = filesWithExt(path.join(dir, sub), '.html');
      for (const file of subHtml) {
        const content = read(path.join(dir, sub, file));
        const auth = detectPageAuth(content);
        const scripts = extractScriptSrcs(content).filter(s => !infraSet.has(s));

        const relFile = `${dirRel.replace(/\/$/, '')}/${sub}/${file}`;
        const scriptCol = scripts.length > 0 ? scripts.map(s => `\`${s}\``).join(', ') : '--';
        const entry = `| \`${relFile}\` | ${auth} | ${scriptCol} |`;
        totalPages++;

        if (auth === 'authenticated') authPages.push(entry);
        else if (auth === 'public') publicPages.push(entry);
        else unknownPages.push(entry);
      }
    }
  }

  lines.push(`**${totalPages} HTML pages**`, '');

  const tableHeader = ['| Page | Auth | Page-Specific JS |', '|------|------|-----------------|'];

  if (authPages.length) {
    lines.push(`## Authenticated Pages (${authPages.length})`);
    lines.push(...tableHeader, ...authPages, '');
  }
  if (publicPages.length) {
    lines.push(`## Public Pages (${publicPages.length})`);
    lines.push(...tableHeader, ...publicPages, '');
  }
  if (unknownPages.length) {
    lines.push(`## Other Pages (${unknownPages.length})`);
    lines.push(...tableHeader, ...unknownPages, '');
  }

  fs.writeFileSync(path.join(OUT, 'pages.md'), lines.join('\n'));
  return totalPages;
}

// ---------------------------------------------------------------------------
// 4. COMPONENTS (Frontend JS)
// ---------------------------------------------------------------------------
function buildComponents() {
  const lines = [`# Frontend Components (generated ${NOW})`, ''];
  let totalComponents = 0;

  const iifes = [];
  const globals = [];
  const controllers = [];
  const classes = [];
  const reactComps = [];
  const others = [];

  for (const dirRel of CONFIG.componentDirs) {
    const dir = path.join(ROOT, dirRel);
    const files = walkDir(dir, dirRel.replace(/\/$/, ''));

    for (const { fullPath, relPath, name } of files) {
      const content = read(fullPath);
      const pattern = detectJsPattern(content);
      const apis = extractApiCalls(content);
      const lineCount = content.split('\n').length;

      const apiStr = apis.length > 0 ? ` -> ${apis.join(', ')}` : '';
      const sizeStr = lineCount > 200 ? ` (${lineCount}L)` : '';
      const entry = `- \`${relPath}\`${sizeStr} -- ${pattern}${apiStr}`;
      totalComponents++;

      if (pattern.startsWith('IIFE')) iifes.push(entry);
      else if (pattern.startsWith('global')) globals.push(entry);
      else if (pattern.startsWith('page')) controllers.push(entry);
      else if (pattern.startsWith('class')) classes.push(entry);
      else if (pattern.startsWith('React')) reactComps.push(entry);
      else others.push(entry);
    }
  }

  lines.push(`**${totalComponents} component files**`, '');

  if (globals.length) {
    lines.push(`## Global Exports (${globals.length})`, ...globals, '');
  }
  if (reactComps.length) {
    lines.push(`## React Components (${reactComps.length})`, ...reactComps, '');
  }
  if (controllers.length) {
    lines.push(`## Page Controllers (${controllers.length})`, ...controllers, '');
  }
  if (classes.length) {
    lines.push(`## Classes (${classes.length})`, ...classes, '');
  }
  if (iifes.length) {
    lines.push(`## Self-Initializing IIFEs (${iifes.length})`, ...iifes, '');
  }
  if (others.length) {
    lines.push(`## Other Scripts (${others.length})`, ...others, '');
  }

  fs.writeFileSync(path.join(OUT, 'components.md'), lines.join('\n'));
  return totalComponents;
}

// ---------------------------------------------------------------------------
// 5. SCHEMA (Firestore / database collections)
// ---------------------------------------------------------------------------
function buildSchema() {
  const lines = [`# Data Schema (generated ${NOW})`, ''];

  const allPaths = new Map(); // collection -> Set of source files

  // Scan all configured dirs for Firestore collection references
  const dirsToScan = [...CONFIG.endpointDirs, ...CONFIG.sharedDirs];
  for (const dirRel of dirsToScan) {
    const dir = path.join(ROOT, dirRel);
    const files = walkDir(dir, dirRel.replace(/\/$/, ''));

    for (const { fullPath, relPath } of files) {
      const content = read(fullPath);
      const paths = extractFirestorePaths(content);
      for (const p of paths) {
        if (!allPaths.has(p)) allPaths.set(p, new Set());
        allPaths.get(p).add(relPath);
      }
    }
  }

  const sorted = [...allPaths.entries()].sort((a, b) => a[0].localeCompare(b[0]));

  if (sorted.length === 0) {
    lines.push('_No Firestore collections detected._');
    fs.writeFileSync(path.join(OUT, 'schema.md'), lines.join('\n'));
    return 0;
  }

  lines.push(`**${sorted.length} Firestore collections** detected`, '');
  lines.push('| Collection | Used By |');
  lines.push('|------------|---------|');

  for (const [collection, files] of sorted) {
    const fileList = [...files].sort().map(f => `\`${f}\``).join(', ');
    lines.push(`| \`${collection}\` | ${fileList} |`);
  }
  lines.push('');

  // Subcollection patterns
  lines.push('## Subcollection Patterns', '');
  const subColls = new Set();
  for (const dirRel of dirsToScan) {
    const dir = path.join(ROOT, dirRel);
    const files = walkDir(dir, dirRel.replace(/\/$/, ''));
    for (const { fullPath } of files) {
      const content = read(fullPath);
      const matches = content.matchAll(/\.doc\([^)]*\)\.collection\(\s*['"]([^'"]+)['"]\s*\)/g);
      for (const m of matches) subColls.add(m[1]);
    }
  }

  if (subColls.size > 0) {
    for (const sc of [...subColls].sort()) {
      lines.push(`- \`{parent}/{id}/${sc}\``);
    }
  } else {
    lines.push('_None detected_');
  }

  fs.writeFileSync(path.join(OUT, 'schema.md'), lines.join('\n'));
  return sorted.length;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
function main() {
  const t0 = Date.now();

  const endpointCount = buildEndpoints();
  const sharedCount = buildShared();
  const pageCount = buildPages();
  const componentCount = buildComponents();
  const schemaCount = buildSchema();

  const elapsed = Date.now() - t0;

  // Write summary README
  const summary = [
    `# Codex Index (generated ${NOW})`,
    '',
    `Built in ${elapsed}ms. Read these files to skip codebase exploration.`,
    '',
    '| File | Contents | Count |',
    '|------|----------|-------|',
    `| [endpoints.md](endpoints.md) | API routes -- methods, auth, flags | ${endpointCount} |`,
    `| [shared.md](shared.md) | Shared module exports + signatures | ${sharedCount} |`,
    `| [pages.md](pages.md) | HTML pages -> JS dependencies | ${pageCount} |`,
    `| [components.md](components.md) | Frontend JS -- pattern, API calls | ${componentCount} |`,
    `| [schema.md](schema.md) | Data collections + who uses them | ${schemaCount} |`,
    '',
    `Total: ~${endpointCount + sharedCount + pageCount + componentCount + schemaCount} indexed items`,
  ].join('\n');

  fs.writeFileSync(path.join(OUT, 'README.md'), summary);

  process.stderr.write(
    `[codex] Indexed ${endpointCount} endpoints, ${sharedCount} shared, ` +
    `${pageCount} pages, ${componentCount} components, ${schemaCount} collections in ${elapsed}ms\n`
  );
}

main();
