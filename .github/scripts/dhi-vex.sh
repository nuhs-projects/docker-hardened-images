#!/usr/bin/env bash
# Download the VEX statements Docker publishes for the DHI images a Dockerfile
# builds on, one file per target and platform:
#   <out dir>/<target>-<os>-<arch>.json   (e.g. vex/runtime-linux-amd64.json)
#
# DHI's VEX marks the CVEs that do not affect its images. Docker Scout applies
# it to DHI images automatically, but not to images built on them, so CI
# scans ours with it (--vex-location) and attaches it to what it pushes.
#
# Usage: dhi-vex.sh <Dockerfile> <out dir> <platform>...
set -euo pipefail

dockerfile=$1
out=$2
shift 2
mkdir -p "$out"

# FROM dhi.io/<image>@sha256:<digest> AS <target>
grep -E '^FROM +dhi\.io/[^ ]+ +AS +[a-z0-9_-]+' "$dockerfile" | while read -r _ ref _ target; do
    for platform in "$@"; do
        file="$out/$target-${platform//\//-}.json"
        # Clean upstream images may have no VEX attestations. Only that explicit
        # response is optional; authentication/network/other errors still fail CI.
        error=$(mktemp)
        if docker scout vex get --platform "$platform" "$ref" --output "$file" >"$error" 2>&1; then
            cat "$error"
            echo "$ref ($platform) -> $file"
        elif grep -q 'no VEX attestations found for image' "$error"; then
            rm -f "$file"
            echo "$ref ($platform): no upstream VEX attestations"
        else
            cat "$error" >&2
            rm -f "$error"
            exit 1
        fi
        rm -f "$error"
    done
done
