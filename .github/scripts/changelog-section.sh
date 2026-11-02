#!/bin/bash
# Prints the CHANGELOG.md section of one version, without its heading.
# Usage: changelog-section.sh X.Y.Z
# It fails if the section does not exist or is empty.
set -euo pipefail

version="$1"
file="${CHANGELOG:-CHANGELOG.md}"

section="$(awk -v v="$version" '
    /^## \[/ { if (found) exit; if (index($0, "## [" v "]") == 1) { found = 1; next } }
    /^\[[^]]+\]: / { if (found) exit }
    found { print }
' "$file")"

if [ -z "$(printf '%s' "$section" | tr -d '[:space:]')" ]; then
    echo "::error file=$file::$file has no section '## [$version]', or the section is empty." >&2
    exit 1
fi
printf '%s\n' "$section"
