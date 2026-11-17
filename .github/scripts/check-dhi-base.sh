#!/usr/bin/env bash
# Fail if any image builds on, or copies from, something other than a Docker
# Hardened Image pinned by digest. See "Why only Docker Hardened Images" in the
# README.
#
# Allowed, in every images/**/Dockerfile:
#   FROM dhi.io/<image>[:<tag>]@sha256:<digest> [AS <stage>]
#   FROM <earlier stage>
#   --from=<earlier stage | stage index | dhi.io digest reference>
#   --mount=...,from=<same>
# Anything else fails, including scratch, other registries, tags without a
# digest, and build arguments in FROM (they could resolve to anything).
#
# Usage: check-dhi-base.sh [<Dockerfile>...]   (default: every image)
set -euo pipefail

dhi='^dhi\.io/[a-z0-9]+([._/-][a-z0-9]+)*(:[A-Za-z0-9_][A-Za-z0-9._-]*)?@sha256:[0-9a-f]{64}$'

if [[ $# -eq 0 ]]; then
    mapfile -t files < <(find images -mindepth 3 -maxdepth 3 -name Dockerfile | sort)
else
    files=("$@")
fi

# A dhi.io digest reference, a stage index already defined, or an earlier
# stage name (case-insensitive, as in Docker)
allowed() {
    local ref=$1 stage
    [[ "$ref" =~ $dhi ]] && return 0
    [[ "$ref" =~ ^[0-9]+$ && "$ref" -lt "$count" ]] && return 0
    for stage in "${stages[@]}"; do
        [[ "${ref,,}" == "$stage" ]] && return 0
    done
    return 1
}

failed=0
for file in "${files[@]}"; do
    stages=()
    count=0
    n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$((n + 1))
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue

        if [[ "$line" =~ ^[[:space:]]*[Ff][Rr][Oo][Mm][[:space:]] ]]; then
            read -r -a words <<<"$line"
            i=1
            while [[ "${words[i]:-}" == --* ]]; do i=$((i + 1)); done
            ref=${words[i]:-}
            if ! allowed "$ref"; then
                echo "::error file=$file,line=$n::FROM '$ref' is not a dhi.io image pinned by digest or an earlier stage"
                failed=1
            fi
            if [[ "${words[i + 1]:-}" =~ ^[Aa][Ss]$ ]]; then
                stages+=("${words[i + 2],,}")
            fi
            count=$((count + 1))
        fi

        # COPY --from=..., RUN --mount=...,from=...
        while read -r ref; do
            [[ -z "$ref" ]] && continue
            if ! allowed "$ref"; then
                echo "::error file=$file,line=$n::from=$ref is not a dhi.io image pinned by digest or an earlier stage"
                failed=1
            fi
        done < <(grep -oE '(--|[ ,])from=[^ ,"]+' <<<"$line" | sed -E 's/^(--|[ ,])from=//')
    done <"$file"
done

if [[ $failed -eq 0 ]]; then
    echo "All ${#files[@]} Dockerfiles build only on dhi.io images pinned by digest"
fi
exit "$failed"
