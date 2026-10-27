#!/usr/bin/env bash
#
# apply-patches.sh — aplica os patches da FiiO na arvore do LineageOS 20.
#
# Uso:
#   ./apply-patches.sh <caminho-da-arvore-lineage>
#
# Os patches sao relativos a raiz do repositorio frameworks/base
# (framework e services vivem no mesmo repo).
#
set -euo pipefail

TREE="${1:?uso: $0 <caminho-da-arvore-lineage>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$TREE/frameworks/base"

[ -d "$BASE" ] || { echo "erro: $BASE nao existe" >&2; exit 1; }

cd "$BASE"

if [ -n "$(git status --porcelain)" ]; then
    echo "erro: frameworks/base tem mudancas nao commitadas" >&2
    exit 1
fi

git checkout -b fiio-jm21-patches 2>/dev/null || git checkout fiio-jm21-patches

echo "== aplicando framework (5)"
for p in "$HERE"/framework/*.patch; do
    echo "   $(basename "$p")"
    git apply --check "$p"
    git apply "$p"
done

echo "== aplicando services (11)"
for p in "$HERE"/services/*.patch; do
    echo "   $(basename "$p")"
    git apply --check "$p"
    git apply "$p"
done

echo
echo "== flags config_fiio_* (61): mesclar manualmente em"
echo "   frameworks/base/core/res/res/values/config.xml"
echo "   origem: $HERE/framework-res/config_fiio.xml"
echo
echo "pronto. Revise com: git -C $BASE diff --stat"
