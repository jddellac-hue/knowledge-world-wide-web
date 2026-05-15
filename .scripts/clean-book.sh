#!/usr/bin/env bash
# scripts/clean-book.sh
# Supprime les artefacts mdbook d'une sous-KB.
# Usage : bash scripts/clean-book.sh <sous-kb>     (lancé par `mise run book:clean -- <sous-kb>`)

set -euo pipefail

SUB="${1:-}"
if [ -z "$SUB" ]; then
  echo "❌ Usage : mise run book:clean -- <sous-kb>" >&2
  exit 1
fi

ROOT="${MISE_PROJECT_ROOT:-$(pwd)}"
KB="$ROOT/$SUB"

if [ ! -d "$KB" ]; then
  echo "❌ Sous-KB introuvable : $KB" >&2
  exit 1
fi

rm -rf "$KB/book" "$KB/src"
rm -f  "$KB/book.toml" "$KB/mermaid.min.js" "$KB/mermaid-init.js"
echo "✅ Artefacts mdbook supprimés pour $SUB ($KB)"
