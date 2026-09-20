#!/usr/bin/env bash
# docs-release-gate.sh — blocks a release whose docs did not move with the code.
#
# Why this exists (2026-09-20):
#
# release.sh printed, on EVERY run, a polite line saying the in-app Help and
# CONTRIBUTING are "not auto-checkable — confirm by hand". Six releases shipped
# that day. The line was read six times and acted on zero times; the in-app Help
# ended up five versions behind, and it took Michael noticing to fix it.
#
# A warning that never blocks is a warning nobody reads. The house rule is
# explicit about the remedy: a correction made by hand a second time means the
# intention failed and a mechanism is due. This is that mechanism.
#
# It does NOT try to judge whether the prose is good — no script can. It checks
# the one thing that is checkable: did the documentation change AT ALL while the
# thing it documents did. Every rule can be waived, but only out loud:
#
#   RELEASE_DOC_WAIVER="reason" make release
#
# The reason is printed into the release output, so a skipped gate leaves a
# trace instead of a silence.

set -uo pipefail
cd "$(dirname "$0")/.."

BASE="${1:-$(git describe --tags --abbrev=0 2>/dev/null)}"
WAIVER="${RELEASE_DOC_WAIVER:-}"
FINDINGS=0

echo "▶ [Pre-flight] Docs moved with the code?"

if [ -z "$BASE" ]; then
    echo "  ⚠ No previous tag found — nothing to compare against, gate skipped."
    exit 0
fi

# A base that git cannot resolve makes every `git diff` below return nothing,
# and the gate then reports "✓ documentation moved with the code" while having
# checked precisely nothing. Found on this script's own first test run: the
# caller passed two refs as one argument (zsh does not word-split unquoted
# variables) and the gate cheerfully passed. A check that reports success on a
# broken input is worse than no check — refuse instead.
if ! git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null; then
    echo "  ❌ '$BASE' is not a resolvable git ref — refusing to report a result."
    echo "       Pass a single tag or commit, e.g. $(git describe --tags --abbrev=0 2>/dev/null || echo '<tag>')"
    exit 1
fi
echo "  comparing against $BASE"

changed() { git diff --name-only "$BASE"...HEAD -- "$@" 2>/dev/null | grep -q . ; }
count_changed() { git diff --name-only "$BASE"...HEAD -- "$@" 2>/dev/null | wc -l | tr -d ' ' ; }

fail() {
    echo "  ❌ $1"
    echo "       $2"
    FINDINGS=$((FINDINGS + 1))
}

# ── 1. New Swift files must appear in ARCHITECTURE.md ────────────────────────
# A file nobody can find in the map may as well not exist for the next reader.
while IFS= read -r f; do
    [ -n "$f" ] || continue
    name=$(basename "$f")
    grep -q "$name" ARCHITECTURE.md 2>/dev/null && continue
    fail "New source file not in ARCHITECTURE.md: $name" \
         "Add it to the tree, or waive with a reason."
done < <(git diff --name-only --diff-filter=A "$BASE"...HEAD -- 'Tippi/**/*.swift' 2>/dev/null)

# ── 2. UI/behaviour changed → in-app Help must have moved too ────────────────
# `whatsNewBody` does not count: the release script already forces that one, and
# it is exactly what was kept current while everything else went stale.
if changed 'Tippi/UI' 'Tippi/Core' 'Tippi/LLM'; then
    help_changed=$(git diff "$BASE"...HEAD -- 'Tippi/Resources/*.lproj/Localizable.strings' 2>/dev/null \
                   | grep -c '^+"settings\.help\.[a-zA-Z]*Body"' || true)
    whats_new_only=$(git diff "$BASE"...HEAD -- 'Tippi/Resources/*.lproj/Localizable.strings' 2>/dev/null \
                     | grep -c '^+"settings\.help\.whatsNewBody"' || true)
    if [ "$help_changed" -le "$whats_new_only" ]; then
        fail "Code changed in UI/Core/LLM, but no Help section other than What's New did." \
             "$(count_changed 'Tippi/UI' 'Tippi/Core' 'Tippi/LLM') file(s) changed. Update settings.help.*Body in BOTH languages, or waive."
    fi
fi

# ── 3. Dev workflow changed → CONTRIBUTING must have moved ───────────────────
if changed 'Makefile' 'scripts'; then
    changed 'CONTRIBUTING.md' || fail \
        "Makefile/scripts changed, CONTRIBUTING.md did not." \
        "A workflow only the author knows is not a workflow. Update it, or waive."
fi

# ── 4. User-facing features changed → README and the website must have moved ─
if changed 'Tippi/UI' 'Tippi/Core'; then
    changed 'README.md'     || fail "UI/Core changed, README.md did not." "Update the feature list, or waive."
    changed 'docs/index.html' || fail "UI/Core changed, the website did not." "Update docs/index.html, or waive."
fi

# ── Verdict ──────────────────────────────────────────────────────────────────
if [ "$FINDINGS" -eq 0 ]; then
    echo "  ✓ documentation moved with the code"
    exit 0
fi

if [ -n "$WAIVER" ]; then
    echo ""
    echo "  ⚠ $FINDINGS finding(s) WAIVED: $WAIVER"
    echo "    Recorded here so the skip is visible in the release log."
    exit 0
fi

echo ""
echo "  🛑 $FINDINGS documentation gap(s). This gate exists because the polite"
echo "     version of it was ignored six times in one day (2026-09-20)."
echo "     Fix them, or re-run with an explicit reason:"
echo "       RELEASE_DOC_WAIVER=\"why this release needs no doc change\" make release"
exit 1
