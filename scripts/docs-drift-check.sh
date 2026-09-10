#!/usr/bin/env bash
#
# docs-drift-check.sh — verifies documentation claims against the CODE as the only truth.
#
# Why this exists: the documentation rule has been in .claude/rules/coding since v1.20.3.
# It was still broken four times on 2026-09-10 — docs/pitch.html carried wrong provider and
# prompt counts for five releases, docs/HANDOVER.md's header said v1.6.0 while the app was
# at v2.1.0. A checklist is a request; a gate is a mechanism.
#
# Principle: neighbouring documents are NOT truth. Everything is compared against the code.
#
# NOTE ON LANGUAGE: comments and output are English, but the SEARCH PATTERNS deliberately
# contain German words ("Anbieter", "Stand", "seit"). ARCHITECTURE.md and docs/HANDOVER.md
# are written in German — dropping those words would silently stop matching half the docs.
# Do not "clean this up".
#
# Exit codes: 0 = no drift · 1 = drift found · 2 = the parser itself broke (script bug, not a docs bug)

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

FAILURES=0
ok()  { printf '  ✓ %s\n' "$*"; }
bad() { printf '  ❌ %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
die() { printf '\n🛑 %s\n' "$*" >&2; exit 2; }

# CHANGELOG.md and PRD.md are absent on purpose: both are historical documents whose old
# numbers are correct. PRD.md is explicitly marked as the May scope and is not updated.
DOCS=(README.md ARCHITECTURE.md CLAUDE.md docs/HANDOVER.md docs/ONE-PAGER.md docs/index.html docs/pitch.html)

# ── 1. Read the truth from the code ───────────────────────────────────────────

PROVIDERS=$(awk '
  /static let allProviders: \[LLMProvider\] = \[/ { inblock = 1; next }
  inblock && /^[[:space:]]*\]/                    { exit }
  inblock && /Provider\(\)/                       { n++ }
  END { print n + 0 }
' Tippi/LLM/LLMRouter.swift)

# NOT DemoPrompt.all — that is builtIn PLUS the user's own prompts, so it differs per
# install. The documented number refers to builtIn, minus multi-step chains.
BUILTIN_BLOCK=$(awk '
  /^[[:space:]]*static var builtIn: \[DemoPrompt\]/          { inblock = 1; next }
  inblock && /^[[:space:]]*(private )?static (func|var|let)/ { exit }
  inblock
' Tippi/UI/PromptPopup/DemoPrompt.swift)

BUILTIN=$(printf '%s\n' "$BUILTIN_BLOCK" | grep -c 'id: "' || true)
CHAINS=$(printf '%s\n' "$BUILTIN_BLOCK"  | grep -c 'pipeline:' || true)
PROMPTS=$((BUILTIN - CHAINS))

VERSION=$(grep -E 'MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')

# Sanity gates. A parser that finds nothing must NOT pass as "no drift" — that would be
# exactly the silent failure this script is meant to prevent.
[ "${PROVIDERS:-0}" -ge 2 ] || die "Parser broken: found $PROVIDERS providers in LLMRouter.swift. Did the structure change?"
[ "${BUILTIN:-0}"   -ge 2 ] || die "Parser broken: found $BUILTIN builtIn prompts in DemoPrompt.swift. Did the structure change?"
[ -n "${VERSION:-}" ]       || die "Parser broken: cannot read MARKETING_VERSION from project.yml."

printf '\n▶ Truth from the code\n'
ok "$PROVIDERS providers · $PROMPTS prompts ($BUILTIN builtIn − $CHAINS chain(s)) · version $VERSION"

# ── 2. Recognise historical lines ─────────────────────────────────────────────
# Roadmap and changelog-style lines quote old numbers on purpose ("v1.14.x — now 10
# providers"). Those are correct. Reporting them would make someone "fix" accurate history —
# the case described in CLAUDE.md: a checker warning is not the same as a data error.
is_historical() {
  printf '%s' "$1" | grep -qE 'v[0-9]+\.[0-9]+|drift-ok|seit |Stand [0-9]{4}-'
}

# ── 3. Verify numeric claims ──────────────────────────────────────────────────
check_claims() {
  local label="$1" expected="$2" pattern="$3"
  local found=0 skipped=0
  printf '\n▶ %s (expected: %s)\n' "$label" "$expected"

  while IFS= read -r hit; do
    local file="${hit%%:*}" rest="${hit#*:}"
    local lineno="${rest%%:*}" text="${rest#*:}"

    if is_historical "$text"; then
      skipped=$((skipped + 1))
      continue
    fi

    local claimed
    claimed=$(printf '%s' "$text" | grep -oiE "$pattern" | grep -oE '[0-9]+' | head -1)
    [ -n "$claimed" ] || continue
    found=$((found + 1))

    if [ "$claimed" != "$expected" ]; then
      bad "$file:$lineno claims $claimed, code says $expected"
      printf '       %s\n' "$(printf '%s' "$text" | sed 's/^[[:space:]]*//' | cut -c1-110)"
    fi
  done < <(grep -rniE "$pattern" "${DOCS[@]}" 2>/dev/null || true)

  [ "$found" -gt 0 ] || die "Parser broken: not a single '$label' mention found in the docs. Did the wording change?"
  ok "$found mention(s) checked, $skipped historical skipped"
}

# Patterns are deliberately narrow:
#   (^|[^0-9.])   -> "6.1 Provider" is a section number, not a count
#   ([^-A-Za-z]|$) -> "Provider-Protocol" is a compound word, not a count
check_claims "Provider count" "$PROVIDERS" '(^|[^0-9.])[0-9]+ (KI-)?(Anbieter|[Pp]roviders?)([^-A-Za-z]|$)'
check_claims "Prompt count"   "$PROMPTS"   '(^|[^0-9.])[0-9]+ (built-in |Built-|Demo-?)?[Pp]rompts?([^-A-Za-z]|$)'

# ── 4. Version in document headers ────────────────────────────────────────────
printf '\n▶ Version in document headers (expected: %s)\n' "$VERSION"
version_hits=0
while IFS= read -r hit; do
  file="${hit%%:*}"; rest="${hit#*:}"; lineno="${rest%%:*}"; text="${rest#*:}"
  claimed=$(printf '%s' "$text" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -n "$claimed" ] || continue
  version_hits=$((version_hits + 1))
  if [ "$claimed" != "$VERSION" ]; then
    bad "$file:$lineno header says $claimed, project.yml says $VERSION"
  fi
done < <(grep -rniE '^(Stand|Version|# .*v?[0-9]+\.[0-9]+\.[0-9]+).*[0-9]+\.[0-9]+\.[0-9]+' "${DOCS[@]}" 2>/dev/null || true)
[ "$version_hits" -gt 0 ] && ok "$version_hits version header(s) checked" || ok "no version headers found"

# ── 5. Paths in the ARCHITECTURE tree ─────────────────────────────────────────
# Conservative by design: checks whether a file/folder of that NAME exists at all.
# Catches invented entries (the real case: a "Prompts/" folder that never existed), not
# misplaced ones. Deliberate trade-off — no tree path reconstruction, but no false positives.
printf '\n▶ Paths in the ARCHITECTURE tree\n'
path_checked=0
while IFS= read -r name; do
  path_checked=$((path_checked + 1))
  if ! find Tippi -name "$name" -print -quit 2>/dev/null | grep -q .; then
    bad "ARCHITECTURE.md mentions '$name' — exists nowhere under Tippi/"
  fi
done < <(grep -v '{' ARCHITECTURE.md | grep -oE '[A-Za-z][A-Za-z0-9_]*\.swift' | sort -u)

while IFS= read -r dir; do
  path_checked=$((path_checked + 1))
  if ! find Tippi -type d -name "$dir" -print -quit 2>/dev/null | grep -q .; then
    bad "ARCHITECTURE.md mentions folder '$dir/' — exists nowhere under Tippi/"
  fi
done < <(grep -oE '[├└│]──[[:space:]]+[A-Z][A-Za-z0-9_]*/' ARCHITECTURE.md | grep -oE '[A-Z][A-Za-z0-9_]*' | sort -u)

ok "$path_checked path name(s) checked"

# ── Result ────────────────────────────────────────────────────────────────────
printf '\n'
if [ "$FAILURES" -eq 0 ]; then
  printf '✅ No documentation drift.\n'
  exit 0
fi
printf '🛑 %s documentation drift finding(s). The code is the truth — update the docs, not the code.\n' "$FAILURES"
exit 1
