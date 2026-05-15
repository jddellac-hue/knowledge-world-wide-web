---
name: mdbook
description: mdbook (Rust) — générateur statique de livres Markdown. Documente la chaîne complète mdbook + Chrome headless + mermaid pour générer HTML navigable + PDF imprimable depuis une KB Markdown, avec symlinks vers contenu source, build reproductible via mise et pièges connus (overrides CSS, print/HTML, génération outline PDF, frontmatter YAML).
---

# mdbook — générateur de livres Markdown

[mdbook](https://rust-lang.github.io/mdBook/) est un générateur statique écrit en Rust qui transforme un dossier de fichiers Markdown en **site HTML navigable** (sidebar, recherche full-text) et en **page imprimable** (`print.html`) consommable par un moteur d'impression (Chrome headless) pour produire un PDF.

Adopté quand on veut publier ou imprimer une KB Markdown **sans dupliquer son contenu** : la KB reste source de vérité, mdbook lit via symlinks, le `book/` produit est un artefact de build à ignorer en git.

---

## Pourquoi mdbook plutôt que pandoc / mkdocs / Hugo

| Outil | Stack | Force | Limite |
|---|---|---|---|
| **mdbook** | Rust binaire unique | Une seule commande `mdbook build` produit HTML + `print.html`. Préprocesseurs simples (mermaid, toc). Pas de dépendance LaTeX. | Sidebar/templates plus rigides que mkdocs Material. |
| pandoc | Haskell | Conversion universelle (Markdown → LaTeX → PDF, DOCX, EPUB). | Dependance LaTeX lourde, configuration plus complexe pour styling. |
| weasyprint | Python | Très bon CSS print, HTML → PDF natif sans Chrome. | Pas trouvé toujours installé, courbe CSS `@page` à apprendre. |
| mkdocs / Hugo | Python / Go | Sites doc plus flashy, plugins riches. | Pas de mode print-as-PDF first-class (extensions tierces). |

**Choix par défaut pour une KB versionnée en git, multi-domaine** : mdbook + Chrome headless. Reproductible, dépendances minimales, build 5-10 secondes.

---

## Carte de navigation

| Sujet | Fichier |
|---|---|
| Pipeline complet KB → HTML + PDF | [`experience/mdbook-pdf-pipeline.md`](experience/mdbook-pdf-pipeline.md) |

---

## Patterns à retenir

### Symlinks `src/` → contenu KB (ne jamais dupliquer)

Plutôt que de copier les `.md` dans `src/` (que mdbook attend par défaut), créer des symlinks :

```bash
mkdir -p src
ln -sfn ../README.md      src/README.md
ln -sfn ../guides         src/guides
ln -sfn ../experience     src/experience
```

mdbook les suit. Avantages : (a) une seule source de vérité, (b) `src/` peut aller en `.gitignore`, (c) chaque édition côté KB est immédiatement visible au prochain `mdbook build`.

### `.gitignore` strict pour build artifacts

Tout ce que mdbook génère ou que la chaîne PDF produit doit être **hors git** :

```gitignore
book/
src/
book.toml
mermaid.*.js
print-extras.css
preamble-class.js
*.pdf
```

Règle de posture : **jamais de build artifact en commit**. Quand on initialise mdbook dans un repo doc/KB, le `.gitignore` se met à jour avant le 1er commit d'outillage.

### Outillage build dans `.scripts/` (caché)

Convention durable : les scripts de build (`build-book.sh`, `clean-book.sh`) vivent dans **`.scripts/`** (dossier caché), pas `scripts/`. Raison : la racine du repo doc/KB doit lister du contenu, pas de l'outillage. L'utilisateur qui ouvre le repo voit `guides/`, `experience/`, `README.md` — pas du tooling.

### Tâche `mise` paramétrable

Pour un repo monolithique (un seul `book.toml`) :

```toml
# mise.toml
[tasks.book]
description = "Build mdbook + PDF"
run = "bash .scripts/build-book.sh"
```

Pour un repo multi-sous-KB (ex : `knowledge-world-wide-web/sre/`, `kafka/`, etc.) :

```toml
[tasks.book]
description = "Build mdbook + PDF d'une sous-KB"
run = "bash .scripts/build-book.sh"
```

Et le script reçoit `$1` correctement (ex : `mise run book -- sre`).

> ⚠️ **Piège** : `tasks.book = "sh -c ..."` inline ne propage pas `$1`. Toujours passer par un script externe (`bash .scripts/build-book.sh`) qui voit ses arguments positionnels.

---

## Anti-patterns

| Anti-pattern | D'où ça vient | Conséquence |
|---|---|---|
| Copier les `.md` dans `src/` au lieu de symlinks | habitude mdbook tutorial | doublons à maintenir, drift KB ↔ build |
| Commiter `book/` ou `src/` | oubli `.gitignore` | repo pollué, conflits inutiles |
| Frontmatter YAML `--- name:... ---` non strippé avant build | mdbook ne parse pas le frontmatter | h1 dupliqué + setext h2 parasite (cf. `experience/mdbook-pdf-pipeline.md` §Frontmatter) |
| Sidebar fixée par CSS sans `!important` triple | runtime JS mdbook réécrit la CSS variable au load | overrides ignorés (cf. piège 30 min) |
| `--page-padding` ou `--content-max-width` non override en `@media print` | mdbook applique aussi aux PDF | marges/largeurs gaspillées en print |

---

## Cheatsheet — commandes utiles

```bash
mdbook init                  # squelette book.toml + src/SUMMARY.md
mdbook build                 # produit book/index.html + book/print.html
mdbook serve                 # dev server avec live reload
mdbook clean                 # supprime book/

# PDF via Chrome headless (laisse mermaid s'exécuter)
google-chrome --headless --no-sandbox \
  --no-pdf-header-footer \
  --virtual-time-budget=30000 \
  --print-to-pdf=book/book.pdf \
  file://$(pwd)/book/print.html
```

---

## Glossaire rapide

- **`book.toml`** — config du projet mdbook (titre, auteurs, src dir, build dir, préprocesseurs)
- **`SUMMARY.md`** — table des matières source pour mdbook (chaque `- [Titre](path.md)` devient un chapitre)
- **`print.html`** — page unique générée par mdbook concaténant tous les chapitres pour impression
- **Préprocesseur** — plugin Rust qui transforme l'AST avant rendu (ex : `mdbook-mermaid` injecte mermaid.min.js)
- **`virtual-time-budget`** — flag Chrome headless qui simule N ms d'exécution JS avant capture (laisse mermaid rendre les SVG)
