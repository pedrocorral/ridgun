#!/usr/bin/env bash
# Build the standalone interactive HTML books (docs/book/index.html and es/ca/gl/eu/en/pt/sv editions) from the Markdown chapters.
set -euo pipefail

BOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALL_LANGS=("es" "ca" "gl" "eu" "en" "pt" "sv")

make_lang_bar_html() {
  local active_code="$1"
  local is_root="$2"
  local html=""
  for code in "${ALL_LANGS[@]}"; do
    local label="${code^^}"
    local href=""
    if [[ "$is_root" == "true" ]]; then
      href="${code}/index.html"
    elif [[ "$code" == "$active_code" ]]; then
      href="index.html"
    else
      href="../${code}/index.html"
    fi
    if [[ "$code" == "$active_code" ]]; then
      html+="<a class=\"lang-link active\" href=\"${href}\">${label}</a>"
    else
      html+="<a class=\"lang-link\" href=\"${href}\">${label}</a>"
    fi
  done
  printf '%s' "$html"
}

write_template_prefix() {
  local html_lang="$1"
  local page_title="$2"
  local lang_bar_html="$3"
  local brand_title="$4"
  local brand_subtitle="$5"
  local search_placeholder="$6"
  local footer_text="$7"
  local theme_label="$8"

  cat <<EOF
<!DOCTYPE html>
<html lang="${html_lang}" data-theme="dark">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${page_title}</title>
  <style>
    :root, [data-theme="dark"] {
      --bg: #0f141c;
      --bg-sidebar: #141b26;
      --bg-card: #18212f;
      --bg-code: #0b0f16;
      --border: #263246;
      --text: #e6edf3;
      --text-muted: #94a3b8;
      --accent: #38bdf8;
      --accent-soft: rgba(56, 189, 248, 0.14);
      --kw: #ff7b72;
      --ty: #79c0ff;
      --fn: #d2a8ff;
      --str: #a5d6ff;
      --num: #f2cc60;
      --com: #6e7681;
      --op: #ffa657;
      --shadow: 0 8px 24px rgba(0, 0, 0, 0.35);
    }
    [data-theme="light"] {
      --bg: #f8fafc;
      --bg-sidebar: #f1f5f9;
      --bg-card: #ffffff;
      --bg-code: #0f172a;
      --border: #cbd5e1;
      --text: #0f172a;
      --text-muted: #475569;
      --accent: #0284c7;
      --accent-soft: rgba(2, 132, 199, 0.12);
      --kw: #ff7b72;
      --ty: #79c0ff;
      --fn: #d2a8ff;
      --str: #a5d6ff;
      --num: #f2cc60;
      --com: #94a3b8;
      --op: #ffa657;
      --shadow: 0 4px 16px rgba(15, 23, 42, 0.08);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Inter, Roboto, sans-serif;
      background: var(--bg);
      color: var(--text);
      line-height: 1.72;
      display: flex;
      min-height: 100vh;
    }
    /* Sidebar */
    aside.sidebar {
      width: 310px;
      background: var(--bg-sidebar);
      border-right: 1px solid var(--border);
      display: flex;
      flex-direction: column;
      position: fixed;
      top: 0;
      bottom: 0;
      left: 0;
      z-index: 20;
      overflow-y: auto;
    }
    .brand {
      padding: 1.35rem 1.25rem 1rem;
      border-bottom: 1px solid var(--border);
    }
    .brand-top {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 0.45rem;
    }
    .brand-badge {
      display: inline-block;
      font-size: 0.72rem;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: var(--accent);
      background: var(--accent-soft);
      padding: 0.2rem 0.55rem;
      border-radius: 999px;
    }
    .lang-bar {
      display: flex;
      gap: 0.25rem;
    }
    .lang-link {
      font-size: 0.72rem;
      font-weight: 600;
      text-decoration: none;
      color: var(--text-muted);
      padding: 0.16rem 0.42rem;
      border-radius: 5px;
      border: 1px solid var(--border);
    }
    .lang-link:hover, .lang-link.active {
      color: var(--accent);
      border-color: var(--accent);
      background: var(--accent-soft);
    }
    .brand h1 {
      margin: 0;
      font-size: 1.25rem;
      font-weight: 800;
      letter-spacing: -0.02em;
    }
    .brand p {
      margin: 0.25rem 0 0;
      font-size: 0.83rem;
      color: var(--text-muted);
    }
    .search-box {
      padding: 0.85rem 1.1rem;
      border-bottom: 1px solid var(--border);
    }
    .search-box input {
      width: 100%;
      padding: 0.55rem 0.75rem;
      border-radius: 8px;
      border: 1px solid var(--border);
      background: var(--bg);
      color: var(--text);
      font-size: 0.88rem;
      outline: none;
    }
    .search-box input:focus {
      border-color: var(--accent);
    }
    .nav-list {
      list-style: none;
      padding: 0.75rem 0.65rem 1.5rem;
      margin: 0;
      flex: 1;
    }
    .nav-item {
      margin-bottom: 0.25rem;
    }
    .nav-btn {
      width: 100%;
      text-align: left;
      background: transparent;
      border: none;
      color: var(--text-muted);
      padding: 0.62rem 0.75rem;
      border-radius: 8px;
      font-size: 0.9rem;
      cursor: pointer;
      display: flex;
      align-items: flex-start;
      gap: 0.55rem;
      transition: all 0.15s ease;
      line-height: 1.38;
    }
    .nav-btn:hover {
      background: var(--accent-soft);
      color: var(--text);
    }
    .nav-btn.active {
      background: var(--accent-soft);
      color: var(--accent);
      font-weight: 600;
    }
    .nav-num {
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      font-size: 0.78rem;
      opacity: 0.8;
      min-width: 1.5rem;
      padding-top: 0.08rem;
    }
    .sidebar-footer {
      padding: 0.85rem 1.1rem;
      border-top: 1px solid var(--border);
      display: flex;
      justify-content: space-between;
      align-items: center;
      font-size: 0.8rem;
      color: var(--text-muted);
    }
    .theme-btn {
      background: var(--bg-card);
      color: var(--text);
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 0.35rem 0.65rem;
      font-size: 0.8rem;
      cursor: pointer;
    }
    /* Main content */
    main.reader {
      margin-left: 310px;
      flex: 1;
      display: flex;
      justify-content: center;
      padding: 2.5rem 2rem 5rem;
    }
    article.chapter {
      max-width: 820px;
      width: 100%;
    }
    article.chapter h1 {
      font-size: 2.15rem;
      line-height: 1.22;
      margin-top: 0;
      margin-bottom: 1.25rem;
      letter-spacing: -0.025em;
      border-bottom: 1px solid var(--border);
      padding-bottom: 0.85rem;
    }
    article.chapter h2 {
      font-size: 1.48rem;
      margin-top: 2.6rem;
      margin-bottom: 0.85rem;
      color: var(--accent);
      letter-spacing: -0.015em;
    }
    article.chapter h3 {
      font-size: 1.16rem;
      margin-top: 1.8rem;
      margin-bottom: 0.6rem;
    }
    article.chapter p {
      margin: 0 0 1.1rem;
    }
    article.chapter ul, article.chapter ol {
      margin: 0 0 1.25rem;
      padding-left: 1.45rem;
    }
    article.chapter li {
      margin-bottom: 0.4rem;
    }
    article.chapter hr {
      border: none;
      border-top: 1px solid var(--border);
      margin: 2.2rem 0;
    }
    article.chapter blockquote {
      margin: 1.35rem 0;
      padding: 0.9rem 1.15rem;
      border-left: 4px solid var(--accent);
      background: var(--accent-soft);
      border-radius: 0 8px 8px 0;
    }
    article.chapter blockquote p:last-child {
      margin-bottom: 0;
    }
    /* Code blocks */
    .code-wrapper {
      position: relative;
      margin: 1.25rem 0 1.5rem;
      border-radius: 10px;
      overflow: hidden;
      border: 1px solid var(--border);
      background: var(--bg-code);
      box-shadow: var(--shadow);
    }
    .code-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 0.42rem 0.9rem;
      background: rgba(255, 255, 255, 0.04);
      border-bottom: 1px solid rgba(255, 255, 255, 0.07);
      font-size: 0.75rem;
      color: #94a3b8;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    }
    .copy-btn {
      background: rgba(255, 255, 255, 0.08);
      color: #e2e8f0;
      border: 1px solid rgba(255, 255, 255, 0.14);
      border-radius: 5px;
      padding: 0.18rem 0.55rem;
      font-size: 0.73rem;
      cursor: pointer;
    }
    .copy-btn:hover {
      background: rgba(56, 189, 248, 0.25);
    }
    pre {
      margin: 0;
      padding: 1rem 1.15rem;
      overflow-x: auto;
      font-family: "JetBrains Mono", "Fira Code", ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      font-size: 0.89rem;
      line-height: 1.58;
      color: #e6edf3;
    }
    p code, li code, td code {
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      font-size: 0.86em;
      background: var(--accent-soft);
      color: var(--accent);
      padding: 0.15rem 0.38rem;
      border-radius: 5px;
    }
    /* Tables */
    .table-wrap {
      overflow-x: auto;
      margin: 1.35rem 0;
      border: 1px solid var(--border);
      border-radius: 10px;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.92rem;
    }
    th, td {
      padding: 0.7rem 0.95rem;
      border-bottom: 1px solid var(--border);
      text-align: left;
    }
    th {
      background: var(--bg-sidebar);
      font-weight: 700;
    }
    tr:last-child td {
      border-bottom: none;
    }
    /* Syntax tokens */
    .rg-com { color: var(--com); font-style: italic; }
    .rg-kw  { color: var(--kw); font-weight: 600; }
    .rg-ty  { color: var(--ty); font-weight: 600; }
    .rg-str { color: var(--str); }
    .rg-num { color: var(--num); }
    .rg-op  { color: var(--op); font-weight: 600; }
    /* Chapter pager */
    .pager {
      margin-top: 3.5rem;
      padding-top: 1.5rem;
      border-top: 1px solid var(--border);
      display: flex;
      justify-content: space-between;
      gap: 1rem;
    }
    .pager-btn {
      flex: 1;
      padding: 0.9rem 1.1rem;
      border-radius: 10px;
      border: 1px solid var(--border);
      background: var(--bg-card);
      color: var(--text);
      cursor: pointer;
      text-align: left;
      transition: border-color 0.15s ease;
    }
    .pager-btn.next { text-align: right; }
    .pager-btn:hover { border-color: var(--accent); }
    .pager-label {
      display: block;
      font-size: 0.76rem;
      color: var(--text-muted);
      margin-bottom: 0.2rem;
    }
    .pager-title {
      font-weight: 600;
      color: var(--accent);
      font-size: 0.95rem;
    }
    .search-results {
      margin-bottom: 2rem;
      padding: 1rem 1.2rem;
      border-radius: 10px;
      border: 1px solid var(--accent);
      background: var(--bg-card);
    }
    .search-hit {
      padding: 0.6rem 0;
      border-bottom: 1px solid var(--border);
      cursor: pointer;
    }
    .search-hit:last-child { border-bottom: none; }
    .search-hit-title { color: var(--accent); font-weight: 600; }
    .search-hit-snippet { font-size: 0.86rem; color: var(--text-muted); }
    @media (max-width: 860px) {
      aside.sidebar { position: static; width: 100%; border-right: none; border-bottom: 1px solid var(--border); }
      body { flex-direction: column; }
      main.reader { margin-left: 0; padding: 1.5rem 1.1rem 3rem; }
    }
  </style>
</head>
<body>
  <aside class="sidebar">
    <div class="brand">
      <div class="brand-top">
        <span class="brand-badge">Ridgun v0.9.3</span>
        <div class="lang-bar">${lang_bar_html}</div>
      </div>
      <h1>${brand_title}</h1>
      <p>${brand_subtitle}</p>
    </div>
    <div class="search-box">
      <input type="search" id="searchInput" placeholder="${search_placeholder}" />
    </div>
    <ul class="nav-list" id="navList"></ul>
    <div class="sidebar-footer">
      <span>${footer_text}</span>
      <button class="theme-btn" id="themeBtn" type="button">${theme_label}</button>
    </div>
  </aside>

  <main class="reader">
    <article class="chapter" id="chapterContent"></article>
  </main>

  <script>
EOF
}

write_template_suffix() {
  cat <<'EOF'
    let currentIdx = 0;

    function escapeHtml(s) {
      return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function highlightRidgun(code) {
      return code.split("\n").map(line => {
        const comIdx = (() => {
          let inD = false, inS = false;
          for (let i = 0; i < line.length - 1; i++) {
            if (line[i] === "\\") { i++; continue; }
            if (line[i] === '"' && !inS) inD = !inD;
            else if (line[i] === "'" && !inD) inS = !inS;
            else if (!inD && !inS && line[i] === "-" && line[i+1] === "-") return i;
          }
          return -1;
        })();
        const codePart = comIdx >= 0 ? line.slice(0, comIdx) : line;
        const comPart = comIdx >= 0 ? line.slice(comIdx) : "";
        let html = escapeHtml(codePart);
        // Strings
        html = html.replace(/("([^"\\]|\\.)*"|'[^']*')/g, '<span class="rg-str">$1</span>');
        // Keywords
        html = html.replace(/\b(fn|op|type|import|mut|otherwise|with|region|do|global|context|shared|atomic|hardware|echo|and|or|xor|not)\b/g, '<span class="rg-kw">$1</span>');
        // Types & constructors
        html = html.replace(/\b(Int|Real|String|Char|Bool|Tensor|Option|Result|Some|None|Ok|Err|OutOfMemory|Timeout|True|False)\b/g, '<span class="rg-ty">$1</span>');
        // Operators
        html = html.replace(/(::|=&gt;|-&gt;|&lt;-|\|\|\.|\|\||\|\.)/g, '<span class="rg-op">$1</span>');
        // Numbers & byte units
        html = html.replace(/\b(0x[0-9a-fA-F_]+|[0-9][0-9_]*(_KB|_MB|_GB)?(\.[0-9]+)?)\b/g, '<span class="rg-num">$1</span>');
        if (comPart) {
          html += '<span class="rg-com">' + escapeHtml(comPart) + '</span>';
        }
        return html;
      }).join("\n");
    }

    function formatInline(text) {
      let out = escapeHtml(text);
      out = out.replace(/`([^`]+)`/g, "<code>$1</code>");
      out = out.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
      out = out.replace(/\*([^*]+)\*/g, "<em>$1</em>");
      out = out.replace(/\$O\(([^)]+)\)\$/g, "<code>O($1)</code>");
      out = out.replace(/\$\\rightarrow\$/g, "&rarr;");
      out = out.replace(/\$1024\^2\$/g, "1024<sup>2</sup>");
      out = out.replace(/\$1024\^3\$/g, "1024<sup>3</sup>");
      out = out.replace(/\$1024\$/g, "1024");
      return out;
    }

    function renderMarkdown(md) {
      const lines = md.split("\n");
      let html = "";
      let i = 0;
      while (i < lines.length) {
        const line = lines[i];
        // Fenced code block
        if (line.startsWith("```")) {
          const lang = line.slice(3).trim() || "ridgun";
          i++;
          const buf = [];
          while (i < lines.length && !lines[i].startsWith("```")) {
            buf.push(lines[i]);
            i++;
          }
          i++; // skip closing ```
          const rawCode = buf.join("\n");
          const bodyHtml = (lang === "ridgun" || lang === "") ? highlightRidgun(rawCode) : escapeHtml(rawCode);
          html += `<div class="code-wrapper"><div class="code-header"><span>${escapeHtml(lang)}</span><button class="copy-btn" onclick="copyCode(this)">${escapeHtml(UI_STRINGS.copy_label)}</button></div><pre data-raw="${ encodeURIComponent(rawCode) }"><code>${bodyHtml}</code></pre></div>`;
          continue;
        }
        // Horizontal rule
        if (/^---+$/.test(line.trim())) {
          html += "<hr />";
          i++;
          continue;
        }
        // Headings
        if (line.startsWith("# ")) {
          html += `<h1>${formatInline(line.slice(2).trim())}</h1>`;
          i++;
          continue;
        }
        if (line.startsWith("## ")) {
          html += `<h2>${formatInline(line.slice(3).trim())}</h2>`;
          i++;
          continue;
        }
        if (line.startsWith("### ")) {
          html += `<h3>${formatInline(line.slice(4).trim())}</h3>`;
          i++;
          continue;
        }
        // Table
        if (line.trim().startsWith("|") && i + 1 < lines.length && /^\|[\s:-]+\|/.test(lines[i+1].trim())) {
          const headers = line.trim().slice(1, -1).split("|").map(c => formatInline(c.trim()));
          i += 2;
          const rows = [];
          while (i < lines.length && lines[i].trim().startsWith("|")) {
            rows.push(lines[i].trim().slice(1, -1).split("|").map(c => formatInline(c.trim())));
            i++;
          }
          html += '<div class="table-wrap"><table><thead><tr>' + headers.map(h => `<th>${h}</th>`).join("") + '</tr></thead><tbody>' +
                  rows.map(r => '<tr>' + r.map(c => `<td>${c}</td>`).join("") + '</tr>').join("") + '</tbody></table></div>';
          continue;
        }
        // Blockquote
        if (line.startsWith(">")) {
          const qLines = [];
          while (i < lines.length && lines[i].startsWith(">")) {
            qLines.push(lines[i].replace(/^>\s?/, ""));
            i++;
          }
          html += `<blockquote><p>${qLines.map(formatInline).join("<br/>")}</p></blockquote>`;
          continue;
        }
        // Unordered list
        if (/^\s*-\s+/.test(line)) {
          const items = [];
          while (i < lines.length && /^\s*-\s+/.test(lines[i])) {
            items.push(formatInline(lines[i].replace(/^\s*-\s+/, "")));
            i++;
          }
          html += "<ul>" + items.map(it => `<li>${it}</li>`).join("") + "</ul>";
          continue;
        }
        // Ordered list
        if (/^\s*\d+\.\s+/.test(line)) {
          const items = [];
          while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) {
            items.push(formatInline(lines[i].replace(/^\s*\d+\.\s+/, "")));
            i++;
          }
          html += "<ol>" + items.map(it => `<li>${it}</li>`).join("") + "</ol>";
          continue;
        }
        // Empty line
        if (!line.trim()) {
          i++;
          continue;
        }
        // Paragraph
        const pLines = [];
        while (i < lines.length && lines[i].trim() && !lines[i].startsWith("#") && !lines[i].startsWith("```") && !lines[i].startsWith(">") && !lines[i].trim().startsWith("|") && !/^---+$/.test(lines[i].trim()) && !/^\s*(-\s+|\d+\.\s+)/.test(lines[i])) {
          pLines.push(formatInline(lines[i]));
          i++;
        }
        html += `<p>${pLines.join(" ")}</p>`;
      }
      return html;
    }

    window.copyCode = function(btn) {
      const pre = btn.closest(".code-wrapper").querySelector("pre");
      const raw = decodeURIComponent(pre.getAttribute("data-raw"));
      navigator.clipboard.writeText(raw);
      const old = btn.textContent;
      btn.textContent = UI_STRINGS.copied_label;
      setTimeout(() => { btn.textContent = old; }, 1400);
    };

    function renderSidebar() {
      const nav = document.getElementById("navList");
      nav.innerHTML = CHAPTERS.map((ch, idx) => `
        <li class="nav-item">
          <button class="nav-btn ${idx === currentIdx ? 'active' : ''}" onclick="selectChapter(${idx})">
            <span class="nav-num">${ch.num}</span>
            <span>${escapeHtml(ch.short_title)}</span>
          </button>
        </li>
      `).join("");
    }

    window.selectChapter = function(idx) {
      currentIdx = idx;
      const ch = CHAPTERS[idx];
      location.hash = ch.slug;
      renderSidebar();
      let pagerHtml = '<div class="pager">';
      if (idx > 0) {
        pagerHtml += `<button class="pager-btn prev" onclick="selectChapter(${idx - 1})"><span class="pager-label">${UI_STRINGS.prev_label}</span><span class="pager-title">${escapeHtml(CHAPTERS[idx - 1].title)}</span></button>`;
      } else {
        pagerHtml += '<div></div>';
      }
      if (idx + 1 < CHAPTERS.length) {
        pagerHtml += `<button class="pager-btn next" onclick="selectChapter(${idx + 1})"><span class="pager-label">${UI_STRINGS.next_label}</span><span class="pager-title">${escapeHtml(CHAPTERS[idx + 1].title)}</span></button>`;
      }
      pagerHtml += '</div>';
      document.getElementById("chapterContent").innerHTML = renderMarkdown(ch.markdown) + pagerHtml;
      window.scrollTo({ top: 0, behavior: "smooth" });
    };

    document.getElementById("searchInput").addEventListener("input", (e) => {
      const q = e.target.value.trim().toLowerCase();
      if (q.length < 2) {
        selectChapter(currentIdx);
        return;
      }
      const hits = [];
      CHAPTERS.forEach((ch, idx) => {
        const lines = ch.markdown.split("\n");
        for (const l of lines) {
          if (l.toLowerCase().includes(q)) {
            hits.push({ idx, title: ch.title, snippet: l.replace(/^[#>*-]+\s*/, "").slice(0, 140) });
            break;
          }
        }
      });
      const box = hits.length
        ? `<div class="search-results"><strong>${escapeHtml(UI_STRINGS.search_hits_label)} "${escapeHtml(q)}" (${hits.length}):</strong>` +
          hits.map(h => `<div class="search-hit" onclick="document.getElementById('searchInput').value=''; selectChapter(${h.idx})"><div class="search-hit-title">${escapeHtml(h.title)}</div><div class="search-hit-snippet">${escapeHtml(h.snippet)}</div></div>`).join("") +
          `</div>`
        : `<div class="search-results">${escapeHtml(UI_STRINGS.search_empty_label)} "${escapeHtml(q)}".</div>`;
      document.getElementById("chapterContent").innerHTML = box + renderMarkdown(CHAPTERS[currentIdx].markdown);
    });

    document.getElementById("themeBtn").addEventListener("click", () => {
      const root = document.documentElement;
      root.setAttribute("data-theme", root.getAttribute("data-theme") === "dark" ? "light" : "dark");
    });

    // Initial load from URL hash if present
    const initialSlug = location.hash.replace(/^#/, "");
    const foundIdx = CHAPTERS.findIndex(c => c.slug === initialSlug);
    selectChapter(foundIdx >= 0 ? foundIdx : 0);
  </script>
</body>
</html>
EOF
}

build_edition() {
  local code="$1"
  local target_dir="$2"
  local out_path="$3"
  local html_lang="$4"
  local page_title="$5"
  local brand_title="$6"
  local brand_subtitle="$7"
  local search_placeholder="$8"
  local footer_text="$9"
  local theme_label="${10}"
  local copy_label="${11}"
  local copied_label="${12}"
  local prev_label="${13}"
  local next_label="${14}"
  local search_hits_label="${15}"
  local search_empty_label="${16}"
  local chapter_prefix_re="${17}"
  local is_root="${18}"

  [[ -d "$target_dir" ]] || return 0
  shopt -s nullglob
  local chapter_files=("$target_dir"/[0-9][0-9]-*.md)
  shopt -u nullglob
  [[ ${#chapter_files[@]} -gt 0 ]] || return 0

  # Also regenerate concatenated BOOK.md when present
  if [[ -f "$target_dir/BOOK.md" ]]; then
    cat "${chapter_files[@]}" > "$target_dir/BOOK.md"
  fi

  local chapters_json="["
  local idx=0
  for path in "${chapter_files[@]}"; do
    local num
    printf -v num "%02d" "$idx"
    local base
    base="$(basename "$path")"
    local slug="${base%.md}"
    local first_line
    first_line="$(head -n 1 "$path")"
    local title="${first_line#\# }"
    local short_title
    short_title="$(printf '%s' "$title" | sed -E "s/${chapter_prefix_re}//")"
    local item_json
    item_json="$(jq -c -Rs \
      --arg num "$num" \
      --arg slug "$slug" \
      --arg file "$base" \
      --arg title "$title" \
      --arg short_title "$short_title" \
      '{num: $num, slug: $slug, file: $file, title: $title, short_title: $short_title, markdown: .}' < "$path")"
    if [[ $idx -gt 0 ]]; then
      chapters_json+=", "
    fi
    chapters_json+="$item_json"
    idx=$((idx + 1))
  done
  chapters_json+="]"

  local ui_strings_json
  ui_strings_json="$(jq -c -n \
    --arg copy_label "$copy_label" \
    --arg copied_label "$copied_label" \
    --arg prev_label "$prev_label" \
    --arg next_label "$next_label" \
    --arg search_hits_label "$search_hits_label" \
    --arg search_empty_label "$search_empty_label" \
    '{copy_label: $copy_label, copied_label: $copied_label, prev_label: $prev_label, next_label: $next_label, search_hits_label: $search_hits_label, search_empty_label: $search_empty_label}')"

  local active_lang="$code"
  [[ "$code" == "root" ]] && active_lang="es"
  local lang_bar_html
  lang_bar_html="$(make_lang_bar_html "$active_lang" "$is_root")"

  {
    write_template_prefix "$html_lang" "$page_title" "$lang_bar_html" "$brand_title" "$brand_subtitle" "$search_placeholder" "$footer_text" "$theme_label"
    printf '    const CHAPTERS = %s;\n' "$chapters_json"
    printf '    const UI_STRINGS = %s;\n' "$ui_strings_json"
    write_template_suffix
  } > "$out_path"

  local bytes
  bytes="$(wc -c < "$out_path")"
  echo "[build_book] Generated ${out_path} (${bytes} bytes, ${idx} chapters)"
}

build_edition "es" "$BOOK_DIR/es" "$BOOK_DIR/es/index.html" "es" \
  "El Libro de Ridgun — Guía Completa del Lenguaje" \
  "El Libro de Ridgun" \
  "De cero a experto en programación funcional tabular y de sistemas" \
  "Buscar en el libro (ej. ||, Tensor, RMM2, TCO...)" \
  "9 capítulos (00–08) · Español" \
  "☀️ / 🌙 Tema" "Copiar" "¡Copiado!" "&larr; Capítulo anterior" "Siguiente capítulo &rarr;" \
  "Resultados para" "No se encontraron coincidencias para" \
  "^Cap(í|i)tulo[[:space:]]+[0-9]+[[:space:]]*[:—-][[:space:]]*" "false"

build_edition "ca" "$BOOK_DIR/ca" "$BOOK_DIR/ca/index.html" "ca" \
  "El Llibre de Ridgun — Guia Completa del Llenguatge" \
  "El Llibre de Ridgun" \
  "De zero a expert en programació funcional tabular i de sistemes" \
  "Cerca al llibre (ex. ||, Tensor, RMM2, TCO...)" \
  "9 capítols (00–08) · Català" \
  "☀️ / 🌙 Tema" "Copia" "Copiat!" "&larr; Capítol anterior" "Capítol següent &rarr;" \
  "Resultats per a" "No s'han trobat coincidències per a" \
  "^Cap(í|i)tol[[:space:]]+[0-9]+[[:space:]]*[:—-][[:space:]]*" "false"

build_edition "gl" "$BOOK_DIR/gl" "$BOOK_DIR/gl/index.html" "gl" \
  "O Libro de Ridgun — Guía Completa da Linguaxe" \
  "O Libro de Ridgun" \
  "De cero a experto en programación funcional tabular e de sistemas" \
  "Buscar no libro (ex. ||, Tensor, RMM2, TCO...)" \
  "9 capítulos (00–08) · Galego" \
  "☀️ / 🌙 Tema" "Copiar" "Copiado!" "&larr; Capítulo anterior" "Seguinte capítulo &rarr;" \
  "Resultados para" "Non se atoparon coincidencias para" \
  "^Cap(í|i)tulo[[:space:]]+[0-9]+[[:space:]]*[:—-][[:space:]]*" "false"

build_edition "eu" "$BOOK_DIR/eu" "$BOOK_DIR/eu/index.html" "eu" \
  "Ridgun Liburua — Lengoaiaren Gida Osoa" \
  "Ridgun Liburua" \
  "Hutsetik aditura taula bidezko programazio funtzional eta sistemikoan" \
  "Bilatu liburuan (adib. ||, Tensor, RMM2, TCO...)" \
  "9 kapitulu (00–08) · Euskara" \
  "☀️ / 🌙 Gaia" "Kopiatu" "Kopiatuta!" "&larr; Aurreko kapitulua" "Hurrengo kapitulua &rarr;" \
  "Emaitzak honentzat:" "Ez da bat-etortzerik aurkitu honentzat:" \
  "^([0-9]+\\.[[:space:]]*kapitulua|Kapitulua[[:space:]]+[0-9]+)[[:space:]]*[:—-][[:space:]]*" "false"

build_edition "en" "$BOOK_DIR/en" "$BOOK_DIR/en/index.html" "en" \
  "The Ridgun Book — Complete Language Guide" \
  "The Ridgun Book" \
  "From zero to expert in tabular functional and systems programming" \
  "Search the book (e.g. ||, Tensor, RMM2, TCO...)" \
  "9 chapters (00–08) · English" \
  "☀️ / 🌙 Theme" "Copy" "Copied!" "&larr; Previous chapter" "Next chapter &rarr;" \
  "Results for" "No matches found for" \
  "^Chapter[[:space:]]+[0-9]+[[:space:]]*[:—-][[:space:]]*" "false"

build_edition "pt" "$BOOK_DIR/pt" "$BOOK_DIR/pt/index.html" "pt" \
  "O Livro do Ridgun — Guia Completo da Linguagem" \
  "O Livro do Ridgun" \
  "Do zero a especialista em programação funcional tabular e de sistemas" \
  "Pesquisar no livro (ex. ||, Tensor, RMM2, TCO...)" \
  "9 capítulos (00–08) · Português" \
  "☀️ / 🌙 Tema" "Copiar" "Copiado!" "&larr; Capítulo anterior" "Próximo capítulo &rarr;" \
  "Resultados para" "Nenhuma correspondência encontrada para" \
  "^Cap(í|i)tulo[[:space:]]+[0-9]+[[:space:]]*[:—-][[:space:]]*" "false"

build_edition "sv" "$BOOK_DIR/sv" "$BOOK_DIR/sv/index.html" "sv" \
  "Boken om Ridgun — Komplett Språkguide" \
  "Boken om Ridgun" \
  "Från noll till expert på tabulär funktionell och systemprogrammering" \
  "Sök i boken (t.ex. ||, Tensor, RMM2, TCO...)" \
  "9 kapitel (00–08) · Svenska" \
  "☀️ / 🌙 Tema" "Kopiera" "Kopierad!" "&larr; Föregående kapitel" "Nästa kapitel &rarr;" \
  "Resultat för" "Inga träffar hittades för" \
  "^Kapitel[[:space:]]+[0-9]+[[:space:]]*[:—-][[:space:]]*" "false"

build_edition "root" "$BOOK_DIR/es" "$BOOK_DIR/index.html" "es" \
  "El Libro de Ridgun — Guía Completa del Lenguaje" \
  "El Libro de Ridgun" \
  "De cero a experto en programación funcional tabular y de sistemas" \
  "Buscar en el libro (ej. ||, Tensor, RMM2, TCO...)" \
  "9 capítulos (00–08) · Español" \
  "☀️ / 🌙 Tema" "Copiar" "¡Copiado!" "&larr; Capítulo anterior" "Siguiente capítulo &rarr;" \
  "Resultados para" "No se encontraron coincidencias para" \
  "^Cap(í|i)tulo[[:space:]]+[0-9]+[[:space:]]*[:—-][[:space:]]*" "true"
