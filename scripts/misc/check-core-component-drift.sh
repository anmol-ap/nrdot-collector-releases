#!/usr/bin/env bash
# Copyright New Relic, Inc. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Flag components of the core nrdot-collector distribution that a curated distribution
# neither includes (manifest.yaml) nor deliberately excludes (excluded-core-components.yaml).
# Also flags exclusions that are no longer in core.
#
# Usage: scripts/misc/check-core-component-drift.sh [-s] <distribution>
#   -s  strict: exit 1 on drift. Default: print GitHub warning annotations and exit 0,
#       so core-only changes don't fail CI because of a curated distribution.
#
# Exits 0 if the distribution has no excluded-core-components.yaml (the check is opt-in).

set -euo pipefail

strict=false
while getopts s flag; do
    case "${flag}" in
        s) strict=true;;
        *) exit 2;;
    esac
done
shift $((OPTIND - 1))

if [[ $# -ne 1 ]]; then
    echo "usage: $0 [-s] <distribution>" >&2
    exit 2
fi

DISTRO="$1"
REPO_DIR="$(git rev-parse --show-toplevel)"
CORE_MANIFEST="${REPO_DIR}/distributions/nrdot-collector/manifest.yaml"
DIR="${REPO_DIR}/distributions/${DISTRO}"
MANIFEST="${DIR}/manifest.yaml"
EXCLUDED="${DIR}/excluded-core-components.yaml"

if [[ ! -f "$EXCLUDED" ]]; then
    echo "ℹ️  ${DISTRO}: no excluded-core-components.yaml, skipping check"
    exit 0
fi

# Print "<section>:<component>" for every gomod entry, using the same naming as
# component-inventory.yaml (path suffix after /<category>/, version dropped).
manifest_components() {
    awk '
        /^[a-z]+:/ { section = substr($1, 1, length($1) - 1) }
        /^[[:space:]]*- gomod:/ {
            mod = $3
            singular = substr(section, 1, length(section) - 1)
            sub(".*/" singular "/", "", mod)
            print section ":" mod
        }
    ' "$1" | sort -u
}

# Print "<section>:<component>" for every key in excluded-core-components.yaml.
excluded_components() {
    awk '
        /^[a-z]+:/ { section = substr($1, 1, length($1) - 1); next }
        /^  [^ #][^:]*:/ {
            name = $1
            sub(":$", "", name)
            print section ":" name
        }
    ' "$1" | sort -u
}

core=$(manifest_components "$CORE_MANIFEST")
ours=$(manifest_components "$MANIFEST")
excluded=$(excluded_components "$EXCLUDED")

# In core, but neither in our manifest nor excluded: needs a decision.
undecided=$(comm -23 <(echo "$core") <(sort -u <(echo "$ours") <(echo "$excluded")))
# Excluded, but no longer in core: stale entry.
stale=$(comm -23 <(echo "$excluded") <(echo "$core"))
# Both included and excluded: contradiction.
conflicting=$(comm -12 <(echo "$ours") <(echo "$excluded"))

report() {
    local message="$1" items="$2"
    [[ -n "$items" ]] || return 0
    while read -r item; do
        if [[ "$strict" == true ]]; then
            echo "❌ ${DISTRO}: ${message}: ${item}"
        else
            echo "::warning::${DISTRO}: ${message}: ${item}"
        fi
    done <<< "$items"
}

report "core component not in manifest.yaml or excluded-core-components.yaml" "$undecided"
report "excluded component is no longer in core" "$stale"
report "component is both in manifest.yaml and excluded-core-components.yaml" "$conflicting"

if [[ -z "$undecided$stale$conflicting" ]]; then
    echo "✅ ${DISTRO}: every core component is either included or explicitly excluded"
    exit 0
fi

echo "   Manifest: ${MANIFEST}"
echo "   Excluded: ${EXCLUDED}"
[[ "$strict" == true ]] && exit 1
exit 0
