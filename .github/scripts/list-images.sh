#!/usr/bin/env bash
# Print the images to build as a JSON array for a GitHub Actions matrix:
#   [{"path":"images/python/3.14-debian13","repo":"python","tag":"3.14-debian13"}, ...]
#
# Usage: list-images.sh [<base ref>]
# Without a base ref, every image. With one, only images whose folder changed
# since it, or every image if the shared hardening or CI changed.
set -euo pipefail

all=$(find images -mindepth 3 -maxdepth 3 -name Dockerfile -exec dirname {} \; | sort)

if [[ $# -eq 0 ]]; then
    selected=$all
else
    changed=$(git diff --name-only "$1"...HEAD)
    if grep -qE '^(hardening|\.github)/' <<<"$changed"; then
        selected=$all
    else
        # Changed image folders that still exist (a deleted image builds nothing)
        selected=$(grep -Fxf <(grep -oE '^images/[^/]+/[^/]+' <<<"$changed" | sort -u) <<<"$all" || true)
    fi
fi

for path in $selected; do
    IFS=/ read -r _ repo tag <<<"$path"
    printf '{"path":"%s","repo":"%s","tag":"%s"}\n' "$path" "$repo" "$tag"
done | jq -cs .
