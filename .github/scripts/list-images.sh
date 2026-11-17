#!/usr/bin/env bash
# Print the images to build as a JSON array for a GitHub Actions matrix:
#   [{"path":"images/python/3.14-debian13","repo":"python","tag":"3.14-debian13"}, ...]
#
# Usage: list-images.sh [<base ref>]
# Without a base ref, every image. With one, only the images whose inputs
# changed since it:
#   images/<repo>/<tag>/**   that image (Dockerfile, test.sh, ...)
#   hardening/**             images whose Dockerfile mounts hardening/
#   the build pipeline       every image: build.yml and the scripts it runs
#                            decide how every image is built, scanned and
#                            pushed
# Anything else (README, other workflows, Dependabot config) builds nothing.
set -euo pipefail

pipeline='^\.github/(workflows/build\.yml|scripts/(list-images|dhi-vex)\.sh)$'

all=$(find images -mindepth 3 -maxdepth 3 -name Dockerfile -exec dirname {} \; | sort)

if [[ $# -eq 0 ]]; then
    selected=$all
else
    changed=$(git diff --name-only "$1"...HEAD)
    if grep -qE "$pipeline" <<<"$changed"; then
        selected=$all
    else
        selected=$(
            # Changed image folders that still exist (a deleted image builds nothing)
            grep -Fxf <(grep -oE '^images/[^/]+/[^/]+' <<<"$changed" | sort -u) <<<"$all" || true
            if grep -q '^hardening/' <<<"$changed"; then
                for path in $all; do
                    if grep -q 'source=hardening' "$path/Dockerfile"; then echo "$path"; fi
                done
            fi
        )
        selected=$(sort -u <<<"$selected")
    fi
fi

for path in $selected; do
    IFS=/ read -r _ repo tag <<<"$path"
    printf '{"path":"%s","repo":"%s","tag":"%s"}\n' "$path" "$repo" "$tag"
done | jq -cs .
