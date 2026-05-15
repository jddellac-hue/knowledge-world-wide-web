#!/usr/bin/env bash
# .scripts/build-book.sh — knowledge-world-wide-web
# Génère un mdbook (HTML + PDF) à partir d'une sous-KB.
# Usage : bash .scripts/build-book.sh <sous-kb>     (lancé par `mise run book -- <sous-kb>`)
#
# Variable d'env optionnelle :
#   HTML_ONLY=1  → skip cargo install + chromium + PDF generation. Mode CI
#                  (image sans cargo, sans chromium). mdbook-mermaid optionnel :
#                  s'il est absent, le preprocessor est retiré du book.toml et
#                  les diagrammes Mermaid s'affichent en code brut côté lecteur.

set -euo pipefail

SUB="${1:-}"
[ -z "$SUB" ] && { echo "❌ Usage : mise run book -- <sous-kb>" >&2; exit 1; }

ROOT="${MISE_PROJECT_ROOT:-$(pwd)}"
KB="$ROOT/$SUB"
[ -d "$KB" ] || { echo "❌ Sous-KB introuvable : $KB" >&2; exit 1; }

HTML_ONLY="${HTML_ONLY:-0}"

# ---------------------------------------------------------------------------
# Prérequis
# ---------------------------------------------------------------------------
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
need() { command -v "$1" >/dev/null 2>&1; }

echo "▶ Vérification des prérequis…"
if [ "$HTML_ONLY" = "1" ]; then
  echo "  Mode HTML_ONLY=1 — skip cargo install + chromium + PDF"
  need mdbook || { echo "❌ mdbook absent du PATH (en mode HTML_ONLY, à fournir avant le build)" >&2; exit 1; }
  HAS_MERMAID=0; need mdbook-mermaid && HAS_MERMAID=1
  [ "$HAS_MERMAID" = "0" ] && echo "  ⚠️  mdbook-mermaid absent — preprocessor désactivé, diagrammes en code brut"
  CHROME=""
  PDFINFO_OK=0
else
  need cargo || { echo "❌ cargo absent" >&2; exit 1; }
  need mdbook         || { echo "  → cargo install mdbook…";         cargo install mdbook --quiet; }
  need mdbook-mermaid || { echo "  → cargo install mdbook-mermaid…"; cargo install mdbook-mermaid --quiet; }
  HAS_MERMAID=1

  CHROME=""
  for c in google-chrome chromium chromium-browser; do need "$c" && { CHROME="$c"; break; }; done
  [ -z "$CHROME" ] && { echo "❌ google-chrome / chromium absent" >&2; exit 1; }
  PDFINFO_OK=0; need pdfinfo && PDFINFO_OK=1
  echo "  ✓ cargo, mdbook, mdbook-mermaid, $CHROME"
fi

# ---------------------------------------------------------------------------
# CSS print : densification + page-break + A4 + .keywords
# ---------------------------------------------------------------------------
echo "▶ Génération de print-extras.css"
cat > "$KB/print-extras.css" <<'CSS'
/* Densification HTML écran : élargir le contenu et réduire les marges
   (override des variables mdbook --page-padding, --content-max-width et
   --sidebar-target-width). Le --page-padding doit être >= la largeur de
   .nav-chapters sinon le contenu passe sous les flèches fixed. */
:root {
  --page-padding: 60px;
  --content-max-width: min(1500px, 88vw);
  /* Fallback CSS : 500px par defaut. Le vrai override est pose par
     preamble-class.js en inline-style (non-important) pour laisser
     l'utilisateur resize la sidebar a la souris. */
  --sidebar-target-width: 500px;
}

/* Préambule (page index/README) en pleine largeur (~ double) — la classe
   is-preamble est posée par preamble-class.js sur la page d'accueil. */
body.is-preamble {
  --content-max-width: min(3000px, 88vw);
}

/* Flèche de navigation gauche/droite plus petite et moins large
   pour libérer de l'espace au contenu */
.nav-chapters {
  font-size: 1.5em !important;
  width: 56px !important;
}

@page {
  size: A4;
  margin: 0.4cm 1cm;
}

@media print {
  /* En print, neutraliser --page-padding et --content-max-width
     qui sinon ajoutent leurs marges. Seules les @page margin
     s'appliquent. */
  :root {
    --page-padding: 0 !important;
    --content-max-width: 100% !important;
  }

  body, .content, .content p, .content li, .content td, .content th {
    font-size: 9.5pt !important;
    line-height: 1.42 !important;
  }
  .content h1 { font-size: 17pt   !important; }
  .content h2 { font-size: 13pt   !important; }
  .content h3 { font-size: 11.5pt !important; }
  .content h4 { font-size: 10.5pt !important; }
  .content h5, .content h6 { font-size: 10pt !important; }
  .content code, .content pre { font-size: 8.5pt !important; }
  .content table { font-size: 7.5pt !important; }

  /* Bloc keywords (description du frontmatter, injecté sous le H1) */
  .keywords, .content .keywords, p.keywords {
    font-size: 7.5pt !important;
    color: #555 !important;
    line-height: 1.35 !important;
    margin: -0.3em 0 1em 0 !important;
    font-style: italic;
  }
  .keywords small, .keywords em {
    font-size: inherit !important;
    color: inherit !important;
  }

  .page-break, main > .content > h1 {
    page-break-before: always !important;
  }
  main > .content > h1:first-of-type {
    page-break-before: avoid !important;
  }

  /* Mermaid + SVG : tenir sur une page sans déborder, pas de coupure */
  .mermaid svg, .content svg {
    max-width: 100% !important;
    max-height: 85vh !important;
    width: auto !important;
    height: auto !important;
    display: block;
    margin: 0 auto;
  }
  .mermaid, pre.mermaid, p:has(> svg), figure {
    page-break-inside: avoid !important;
    break-inside: avoid !important;
    text-align: center;
  }

  .content img, .content figure {
    max-width: 100% !important;
    height: auto !important;
  }
  .content table {
    width: 100% !important;
    max-width: 100% !important;
    table-layout: auto !important;
  }
  .content table td, .content table th {
    word-break: normal !important;
    overflow-wrap: break-word !important;
    hyphens: auto;
  }
  .content pre, .content pre code {
    white-space: pre-wrap !important;
    word-break: break-all !important;
    overflow-wrap: anywhere !important;
  }

  .content h2, .content h3, .content h4 { page-break-after: avoid; }
  .content pre, .content table { page-break-inside: avoid; }
}
CSS

# Petit JS qui pose body.is-preamble sur la page index/README pour
# la règle CSS qui élargit le contenu (--content-max-width) du préambule.
cat > "$KB/preamble-class.js" <<'JS'
(function() {
  // is-preamble class sur la page index/README
  var p = window.location.pathname;
  var leaf = p.split('/').pop();
  if (leaf === '' || leaf === 'index.html') {
    document.body.classList.add('is-preamble');
  }
  // Sidebar : 500px par defaut, persistance localStorage de la
  // preference utilisateur. Le drag du handle reste possible (sans
  // important) ; au mouseup, la nouvelle valeur est sauvee.
  var SIDEBAR_KEY = 'mdbook-sidebar-width-custom';
  var savedWidth = localStorage.getItem(SIDEBAR_KEY);
  document.documentElement.style.setProperty(
    '--sidebar-target-width', savedWidth || '500px'
  );
  document.addEventListener('mouseup', function() {
    var current = document.documentElement.style.getPropertyValue('--sidebar-target-width');
    if (current && current !== savedWidth) {
      localStorage.setItem(SIDEBAR_KEY, current);
      savedWidth = current;
    }
  });
})();
JS

# ---------------------------------------------------------------------------
# book.toml
# ---------------------------------------------------------------------------
cd "$KB"
if [ "$HAS_MERMAID" = "1" ]; then
  # Build local : preprocessor mdbook-mermaid pré-rend les blocs ```mermaid en <pre class="mermaid">
  ADDITIONAL_JS='additional-js = ["mermaid.min.js", "mermaid-init.js", "preamble-class.js"]'
  PREPROC_MERMAID='[preprocessor.mermaid]
command = "mdbook-mermaid"'
else
  # Build CI : pas de mdbook-mermaid → rendu client-side via Mermaid.js officiel
  # télécharge depuis jsdelivr (passe via proxy + CA (env interne)) et génère un init JS
  # qui transforme les <pre><code class="language-mermaid"> que mdbook crée par défaut.
  MERMAID_VERSION="10.9.1"
  if [ ! -f mermaid.min.js ]; then
    echo "▶ download mermaid@$MERMAID_VERSION (rendu client-side)"
    curl -sSL "https://cdn.jsdelivr.net/npm/mermaid@${MERMAID_VERSION}/dist/mermaid.min.js" -o mermaid.min.js
  fi
  cat > mermaid-init.js <<'JS'
(function() {
  // Wrap les <pre><code class="language-mermaid">…</code></pre> que mdbook
  // produit (sans preprocessor mdbook-mermaid) en <pre class="mermaid">…</pre>
  // que Mermaid.js sait rendre.
  document.querySelectorAll('pre > code.language-mermaid').forEach(function(code) {
    var pre = code.parentElement;
    pre.className = 'mermaid';
    pre.textContent = code.textContent;
  });
  if (window.mermaid) {
    window.mermaid.initialize({ startOnLoad: true, theme: 'default' });
  }
})();
JS
  ADDITIONAL_JS='additional-js = ["mermaid.min.js", "mermaid-init.js", "preamble-class.js"]'
  PREPROC_MERMAID='# preprocessor.mermaid désactivé (mdbook-mermaid absent) — rendu Mermaid client-side via mermaid.min.js + mermaid-init.js'
fi
cat > book.toml <<TOML
[book]
title = "book-$SUB"
authors = ["KB knowledge-world-wide-web"]
language = "fr"
src = "src"

[output.html]
default-theme = "light"
preferred-dark-theme = "navy"
mathjax-support = false
no-section-label = false
$ADDITIONAL_JS
additional-css = ["print-extras.css"]
smart-punctuation = true

[output.html.print]
enable = true
page-break = true

[output.html.fold]
enable = true
level = 1

[output.html.search]
enable = true
limit-results = 30
boost-title = 2
boost-hierarchy = 2
boost-paragraph = 1
expand = true
heading-split-level = 3

$PREPROC_MERMAID
TOML

# ---------------------------------------------------------------------------
# src/ : copie + strip frontmatter YAML + injection .keywords
# ---------------------------------------------------------------------------
echo "▶ Préparation src/ (copie + strip frontmatter + injection mots-clés)"
rm -rf src && mkdir -p src

# Fonction qui process un .md : strip frontmatter YAML, injecte description
# en bloc .keywords sous le 1er h1, écrit le résultat à $2.
process_md() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if ! head -1 "$src" 2>/dev/null | grep -qx -- '---'; then
    cp "$src" "$dst"; return
  fi
  local desc
  desc=$(awk '
    BEGIN{in_fm=0; in_desc=0; out=""}
    NR==1 && /^---$/ { in_fm=1; next }
    in_fm && /^---$/ { exit }
    in_fm && /^description: */ {
      sub(/^description: *\|? */, "")
      out=$0; in_desc=1; next
    }
    in_fm && in_desc && /^  / {
      sub(/^  /, " "); out=out $0; next
    }
    in_fm && /^[a-zA-Z_-]+:/ { in_desc=0 }
    END { print out }
  ' "$src")
  awk -v desc="$desc" '
    BEGIN{in_fm=0; injected=0}
    NR==1 && /^---$/ { in_fm=1; next }
    in_fm && /^---$/ { in_fm=0; next }
    in_fm { next }
    !injected && /^# / && desc != "" {
      print
      print ""
      printf "<p class=\"keywords\"><em><small>%s</small></em></p>\n", desc
      print ""
      injected=1; next
    }
    { print }
  ' "$src" > "$dst"
}

# Préambule
[ -f README.md ] && process_md README.md src/README.md

# Sous-dossiers connus
KNOWN_DIRS=(guides experience references versions)
LINKED_DIRS=()
for sub in "${KNOWN_DIRS[@]}"; do
  [ -d "$sub" ] || continue
  mkdir -p "src/$sub"
  while IFS= read -r f; do
    process_md "$f" "src/$sub/$(basename "$f")"
  done < <(find "$sub" -maxdepth 1 -name '*.md')
  # Copier les non-.md (images, snippets/…)
  find "$sub" -maxdepth 1 -type f -not -name '*.md' -exec cp {} "src/$sub/" \; 2>/dev/null || true
  LINKED_DIRS+=("$sub")
done

# ---------------------------------------------------------------------------
# SUMMARY.md
# ---------------------------------------------------------------------------
echo "▶ Génération de SUMMARY.md"
section_label() {
  case "$1" in
    guides) echo "Guides";;
    experience) echo "Expérience";;
    references) echo "Références";;
    versions) echo "Versions";;
    *) echo "${1^}";;
  esac
}
extract_title() {
  local f="$1" t
  t=$(grep -m1 '^# ' "$f" 2>/dev/null | sed 's/^# *//' | sed 's/\r$//' | head -c 120)
  [ -z "$t" ] && t=$(basename "$f" .md)
  echo "$t"
}
{
  echo "# Summary"; echo
  if [ -f src/README.md ]; then
    echo "[Préambule](README.md)"; echo
  fi
  for sub in "${LINKED_DIRS[@]}"; do
    echo "# $(section_label "$sub")"; echo
    while IFS= read -r md; do
      [ -e "$md" ] || continue
      echo "- [$(extract_title "$md")]($sub/$(basename "$md"))"
    done < <(find "src/$sub" -maxdepth 1 -name '*.md' | sort)
    echo
  done
} > src/SUMMARY.md

# ---------------------------------------------------------------------------
# Build HTML (+ PDF si non HTML_ONLY)
# ---------------------------------------------------------------------------
if [ "$HAS_MERMAID" = "1" ]; then
  echo "▶ mdbook-mermaid install + mdbook build"
  mdbook-mermaid install . >/dev/null
else
  echo "▶ mdbook build (sans preprocessor mermaid)"
fi
rm -rf book
mdbook build 2>&1 | { grep -E '^(ERROR| INFO HTML)' || true; } | sed 's/^/  /'

if [ "$HTML_ONLY" = "1" ]; then
  echo
  echo "✅ book-$SUB HTML généré (mode HTML_ONLY — pas de PDF)"
  echo "   HTML : $KB/book/index.html"
  echo "   build/ : $(du -sh book | cut -f1)"
  exit 0
fi

echo "▶ Génération PDF (Chrome headless : mermaid + outline + A4)"
PDF="book/book-$SUB.pdf"
"$CHROME" --headless --disable-gpu --no-sandbox \
  --hide-scrollbars --no-pdf-header-footer \
  --generate-pdf-document-outline \
  --virtual-time-budget=30000 --run-all-compositor-stages-before-draw \
  --print-to-pdf="$PDF" \
  "file://$KB/book/print.html" \
  2>&1 | grep -v -E "ERROR:(dbus|google_apis|gcm)" >&2 || true

echo
echo "✅ book-$SUB généré"
echo "   HTML : $KB/book/index.html"
echo "   build/ : $(du -sh book | cut -f1)"
if [ -f "$PDF" ]; then
  echo "   PDF  : $KB/$PDF ($(du -h "$PDF" | cut -f1))"
  [ "$PDFINFO_OK" -eq 1 ] && echo "   pages : $(pdfinfo "$PDF" 2>/dev/null | awk '/^Pages:/{print $2}')"
else
  echo "   ⚠️ PDF non généré"; exit 1
fi
