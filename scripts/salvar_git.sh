#!/usr/bin/env bash
# Faz commit e push do que mudou em data/ e figuras/ (usado pelo GitHub Actions)
set -euo pipefail
msg="${1:-Atualiza dados}"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add data figuras
if git diff --cached --quiet; then
  echo "Sem mudanças."
  exit 0
fi
git commit -m "$msg ($(date -u +%Y-%m-%d))"
for i in 1 2 3; do
  git pull --rebase && git push && exit 0
  sleep 5
done
exit 1
