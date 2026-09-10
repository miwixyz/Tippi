#!/usr/bin/env bash
#
# prune-releases.sh — keeps the newest N GitHub releases, deletes the rest.
#
# House rule: at most 5 releases. Every release breaks it again, so it was being
# fixed by hand — twice on 2026-09-10 alone. That is exactly the kind of "must
# happen every time" step that belongs in a script, not in someone's memory.
#
# Deleting a release removes its DMG irreversibly, so this refuses to touch:
#   - the newest KEEP releases
#   - anything the appcast still points at (deleting those breaks Sparkle for
#     users who have not updated yet — the one failure that must not happen)
#   - git tags (never touched, so every old build stays reproducible)
#
# Usage: prune-releases.sh [--dry-run] [--keep N]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

KEEP=5
DRY_RUN=0
# while + shift, not for-over-"$@": inside a for loop `shift` moves the real
# argument list while the loop keeps iterating its own copy, so `--keep 3` read
# the flag itself as the value. Caught by the dry run.
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --keep)    shift; KEEP="${1:-5}" ;;
        --keep=*)  KEEP="${1#*=}" ;;
        *)         echo "  ⚠ unbekanntes Argument: $1" ;;
    esac
    shift
done

case "${KEEP}" in
    ''|*[!0-9]*) echo "🛑 --keep braucht eine Zahl, bekam: '${KEEP}'" >&2; exit 2 ;;
esac
[ "${KEEP}" -ge 1 ] || { echo "🛑 --keep muss mindestens 1 sein" >&2; exit 2; }

APPCAST="appcast.xml"

echo "▶ Release prune (keeping newest ${KEEP})"

# Newest first — gh lists in that order.
mapfile -t TAGS < <(gh release list --limit 100 --json tagName --jq '.[].tagName')
TOTAL=${#TAGS[@]}

if [ "${TOTAL}" -le "${KEEP}" ]; then
    echo "  ✓ ${TOTAL} release(s) — nothing to prune"
    exit 0
fi

deleted=0
skipped=0
for ((i = KEEP; i < TOTAL; i++)); do
    tag="${TAGS[$i]}"

    # An appcast entry means Sparkle may still hand this URL to a client.
    if [ -f "${APPCAST}" ] && grep -q "/download/${tag}/" "${APPCAST}"; then
        echo "  ⏭  ${tag} — still referenced by ${APPCAST}, kept"
        skipped=$((skipped + 1))
        continue
    fi

    if [ "${DRY_RUN}" -eq 1 ]; then
        echo "  [dry-run] would delete ${tag} (release only, tag kept)"
    else
        # No --cleanup-tag on purpose: the tag is what keeps an old build
        # reproducible after its DMG is gone.
        gh release delete "${tag}" --yes
        echo "  🗑  deleted ${tag} (release only, tag kept)"
    fi
    deleted=$((deleted + 1))
done

remaining=$((TOTAL - deleted))
if [ "${DRY_RUN}" -eq 1 ]; then
    echo "  → would leave ${remaining} release(s); ${skipped} kept because the appcast still points at them"
else
    echo "  ✓ ${remaining} release(s) remain; ${skipped} kept because the appcast still points at them"
fi
