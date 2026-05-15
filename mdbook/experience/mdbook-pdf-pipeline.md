---
name: mdbook-pdf-pipeline
description: Pipeline mdbook + Chrome headless + mdbook-mermaid pour générer HTML navigable et PDF imprimable depuis une KB Markdown. Documente les pièges concrets de cette chaîne (overrides CSS sidebar, --page-padding et --content-max-width en print, génération outline PDF Chrome 119+, frontmatter YAML strippé au build, build artifacts à ignorer en git, heredoc shell avec backticks, --copy-fonts incompatible certaines versions). Pattern validé sur knowledge-world-wide-web et VigilIAnce.
---

# Pipeline mdbook → HTML + PDF — chaîne complète

> Pattern validé sur `knowledge-world-wide-web` (multi-sous-KB : `sre/`, `kafka/`, `quarkus/`, etc.) et sur le repo doc d'une SN interne (monolithique). 1 commande `mise run book` produit HTML navigable + PDF imprimable, mermaid rendu correctement, frontmatter strippé, marges optimisées.

---

## Vue d'ensemble — les 5 étapes

```
1. Symlinks src/ → contenu KB    (ne pas dupliquer)
2. Strip frontmatter YAML        (sinon h1 dupliqué)
3. mdbook build                  (produit book/index.html + book/print.html)
4. Chrome headless --print-to-pdf (laisse mermaid s'exécuter via virtual-time-budget)
5. Vérification anti-régression  (pdftotext + grep marqueurs mermaid bruts)
```

Chaque étape porte un piège connu. Les sections suivantes les documentent dans l'ordre où on les rencontre.

---

## Étape 1 — Strip frontmatter YAML avant build

### Symptôme

Un `.md` qui commence par :

```markdown
---
name: mon-doc
description: Description longue.
---

# Mon document

Contenu...
```

… produit côté HTML mdbook : **deux h1 + un h2 setext parasite**. mdbook injecte un `# Mon document` depuis `SUMMARY.md`, puis le frontmatter (qu'il ne parse pas) est rendu en `<hr>` + setext h2 (les mots `name`, `description` deviennent un titre soulignement), puis le h1 d'origine apparaît.

### Cause

mdbook **ne parse pas le frontmatter YAML** (contrairement à Jekyll/Hugo). Il traite le bloc `---...---` comme du Markdown brut → règle setext (texte souligné de `===` ou `---`) appliquée par accident.

### Résolution

Dans le script de build, **stripper le frontmatter** avant de copier/symlinker dans `src/` :

```bash
strip_frontmatter() {
  awk '
    BEGIN { in_fm=0; done=0 }
    NR==1 && /^---$/ { in_fm=1; next }
    in_fm && /^---$/ { in_fm=0; done=1; next }
    !in_fm { print }
  ' "$1"
}
```

Ré-injecter optionnellement le `description:` comme `<small>` sous le h1 :

```bash
desc=$(grep -m1 '^description:' "$src" | sed 's/^description: *//')
if [ -n "$desc" ]; then
  printf '# %s\n\n<small>%s</small>\n\n' "$title" "$desc" > "$dst"
fi
strip_frontmatter "$src" >> "$dst"
```

---

## Étape 2 — Sidebar resize avec persistance localStorage

### Le piège — runtime JS écrase les overrides CSS

Symptôme : on fixe `--sidebar-target-width: 230px` dans `theme/css/extra.css`, on rebuild, **la sidebar reste à 300px**. Cause : `book-<hash>.js` (généré par mdbook) fait au load :

```js
documentElement.style.setProperty('--sidebar-target-width', '300px');
```

→ inline style bat les règles CSS de fichier, sauf `!important`. Et même avec `!important`, mdbook calcule la largeur via `width: min(var(--sidebar-target-width), 80vw)` côté `.sidebar`, donc il faut aussi forcer `--sidebar-width`.

### Triple override obligatoire

```css
:root {
  --sidebar-target-width: 230px !important;
  --sidebar-width: 230px !important;
}
.sidebar { width: 230px !important; }
```

### Variante avec resize + persistance

Si on veut que l'utilisateur puisse drag-resize et que la valeur persiste entre rebuilds :

```js
// theme/index.hbs ou un additional-js
const KEY = 'mdbook-sidebar-width-custom';
const saved = localStorage.getItem(KEY);
if (saved) {
  document.documentElement.style.setProperty('--sidebar-width', saved + 'px', 'important');
  document.documentElement.style.setProperty('--sidebar-target-width', saved + 'px', 'important');
}
// Hook resize observer pour sauvegarder à la fin du drag
```

`setProperty(prop, val, 'important')` (3e argument) est nécessaire pour battre le runtime mdbook.

---

## Étape 3 — Print CSS : neutraliser les contraintes HTML

mdbook applique ses CSS variables (`--page-padding`, `--content-max-width`) **aussi en print**. Symptôme : marges PDF gonflées, largeur de contenu plafonnée à 1500px alors qu'on veut tout l'A4.

### Override systématique en `@media print`

```css
@media print {
  :root {
    --page-padding: 0 !important;
    --content-max-width: 100% !important;
  }

  /* page mdbook */
  .page-wrapper, .page, main, body {
    padding: 0 !important;
    margin: 0 !important;
    max-width: 100% !important;
  }

  @page {
    size: A4;
    margin: 1.2cm 1cm 1.4cm 1cm;
  }
}
```

### Tables PDF — `word-break` correct

`word-break: break-all` (utile en HTML pour les tables denses) coupe les mots en plein milieu en PDF → illisible. Préférer :

```css
@media print {
  table { font-size: 7.5pt; }
  td, th {
    word-break: normal;
    hyphens: auto;
  }
}
```

---

## Étape 4 — Chrome headless pour le PDF

```bash
google-chrome --headless --no-sandbox \
  --no-pdf-header-footer \
  --virtual-time-budget=30000 \
  --print-to-pdf=book/book.pdf \
  --print-to-pdf-no-header \
  file://$(pwd)/book/print.html
```

### Pourquoi `--virtual-time-budget=30000`

Chrome headless capture immédiatement par défaut → `mermaid.js` n'a pas eu le temps de transformer les blocs ` ```mermaid ` en SVG → **PDF avec code mermaid brut**. `--virtual-time-budget=30000` simule 30 secondes d'exécution JS avant capture (les timers JS s'exécutent en virtual time, sans bloquer le wall clock). 30s couvre 50+ diagrammes.

### Vérification anti-régression

Après chaque build, vérifier que **0 bloc mermaid brut** ne fuit dans le PDF :

```bash
pdftotext book/book.pdf - | grep -c '^```mermaid' || echo 0
# Attendu : 0
```

Si > 0 : (a) augmenter `--virtual-time-budget`, (b) vérifier que `mdbook-mermaid` est bien listé dans `book.toml` `[preprocessor.mermaid]`, (c) vérifier syntaxe mermaid (pièges 11.x).

### Outline PDF (bookmarks viewer) — Chrome 119+

`--generate-pdf-document-outline` (Chrome 119+) injecte les bookmarks (`/Outlines` PDF catalog) **dans le panneau latéral du viewer**, pas en page imprimée. Conséquence :

- Sidebar PDF cliquable visible dans Adobe Reader, Firefox PDF, Evince, Preview
- **Pas de page de table des matières matérialisée** dans le PDF imprimable

### Outline invisible si panneau viewer fermé

Symptôme classique : l'utilisateur ouvre le PDF, ne voit pas l'outline, conclut qu'il n'y en a pas. Toujours documenter les raccourcis viewer :

| Viewer | Raccourci panneau outline |
|---|---|
| Firefox PDF | `F4` |
| Evince (GNOME) | `F9` |
| Adobe Reader | clic icône signet à gauche |
| Preview (macOS) | `View → Table of Contents` ou `Cmd+Opt+3` |

### Vraie TOC matérialisée en pages

Pour avoir une TOC imprimée comme 1ère page :

1. Générer un `00-table-des-matieres.md` à la volée depuis `SUMMARY.md`
2. L'insérer en 1er chapitre du SUMMARY
3. Optionnel : `qpdf --pages ... -- in.pdf` + manipulation `/PageMode /UseOutlines` pour ouvrir le panneau au lancement

---

## Étape 5 — `book.toml` minimal validé

```toml
[book]
title = "<titre>"
authors = ["<auteur>"]
description = "<description>"
src = "src"
language = "fr"

[output.html]
default-theme = "light"
preferred-dark-theme = "ayu"
git-repository-url = "<url>"
additional-css = ["../theme/css/extra.css", "../theme/css/print-extras.css"]
additional-js = ["../theme/js/preamble-class.js"]
mathjax-support = false
# copy-fonts = true   # ⚠️ rejeté par certaines versions, retirer si erreur de build

[output.html.search]
enable = true
limit-results = 30
use-boolean-and = true

[preprocessor.mermaid]
command = "mdbook-mermaid"
```

> ⚠️ **`copy-fonts = true`** est rejeté par certaines versions mdbook (`unknown field 'copy-fonts'`). Si erreur de build, retirer la ligne.

---

## Pièges connexes (debug shell, mermaid)

### Heredoc bash — backticks et dollars dans le message de commit

```bash
# ❌ DANGER — backticks évalués par le shell
git commit -m "fix: bug `important`"

# ❌ DANGER — $VAR expansé
git commit -m "fix: support $TOKEN"

# ✅ Heredoc strict-quoted (single quote autour de EOF)
git commit -F - <<'EOF'
fix: bug `important` avec $VAR littéral
EOF

# ✅ Fichier temp préparé
printf '%s\n' "fix: bug \`important\`" > /tmp/msg.txt
git commit -F /tmp/msg.txt
```

### mdbook ignore les `# Header` (parts) du SUMMARY en print.html

Dans `SUMMARY.md`, un `# Partie 1` est rendu en HTML comme bloc-titre de section, mais **ignoré dans `print.html`**. Pour avoir un saut de page sur chaque section en PDF, transformer chaque part en chapitre "page de garde" avec sub-chapters indentés :

```markdown
# Avant (ignoré en print)
- [Sujet A](sujet-a.md)
- [Sujet B](sujet-b.md)

# Après (saut de page visible en PDF + sidebar)
- [Préambule — Partie 1](partie-1-cover.md)
  - [Sujet A](sujet-a.md)
  - [Sujet B](sujet-b.md)
```

---

## Liens

- Pièges Mermaid 11.x rencontrés dans cette chaîne : [`../../diagramming/mermaid/experience/mermaid-11x-pieges.md`](../../diagramming/mermaid/experience/mermaid-11x-pieges.md)
- mise pour orchestrer le build : [`../../mise/README.md`](../../mise/README.md)
