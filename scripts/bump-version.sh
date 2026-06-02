#!/bin/bash
# bump-version.sh — patch project.yml MARKETING_VERSION + CURRENT_PROJECT_VERSION
# and stamp a CHANGELOG.md header stub for the new release.
#
# Usage:
#   ./scripts/bump-version.sh 1.9.1            # patches files, prints diff, no commit
#   ./scripts/bump-version.sh 1.9.1 --commit   # also commits "chore: bump version to 1.9.1"
#
# project.yml is the single source of truth for VERSION (since 2026-06-02).
# release.env no longer carries a VERSION field.
#
# CURRENT_PROJECT_VERSION in project.yml is mostly for IDE consistency — the
# release pipeline overrides it with `git rev-list --count HEAD` at build time.
# We still bump it to keep local Xcode builds matching the release behaviour.

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <new-version> [--commit]" >&2
    echo "Example: $0 1.9.1" >&2
    exit 2
fi

NEW_VERSION="$1"
COMMIT_FLAG="${2:-}"

# Validate semver-ish X.Y.Z
if ! [[ "${NEW_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "✗ Version '${NEW_VERSION}' is not in X.Y.Z form." >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

PROJECT_FILE="project.yml"
CHANGELOG_FILE="CHANGELOG.md"

if [ ! -f "${PROJECT_FILE}" ]; then
    echo "✗ ${PROJECT_FILE} not found in ${REPO_ROOT}." >&2
    exit 1
fi

CUR_VERSION="$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' "${PROJECT_FILE}")"
CUR_BUILD="$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "${PROJECT_FILE}")"

if [ -z "${CUR_VERSION}" ]; then
    echo "✗ Could not read current MARKETING_VERSION from ${PROJECT_FILE}." >&2
    exit 1
fi

if [ "${CUR_VERSION}" = "${NEW_VERSION}" ]; then
    echo "ℹ️  ${PROJECT_FILE} is already at ${NEW_VERSION} — nothing to bump."
    exit 0
fi

# Compute next build number from git history (matches release.sh logic at build time).
NEW_BUILD="$(git rev-list --count HEAD)"
# release.sh runs after the bump commit, which adds 1 to rev-list count.
# When --commit is set we pre-compute that and store the post-commit value;
# otherwise leave the current value so the project.yml shows the live count.
if [ "${COMMIT_FLAG}" = "--commit" ]; then
    NEW_BUILD=$((NEW_BUILD + 1))
fi

echo "▶ Bumping ${CUR_VERSION} → ${NEW_VERSION}"
echo "  build: ${CUR_BUILD} → ${NEW_BUILD}"

# Patch project.yml (BSD sed-safe in-place edit).
sed -i '' -E "s/(MARKETING_VERSION: )\"[^\"]+\"/\1\"${NEW_VERSION}\"/" "${PROJECT_FILE}"
sed -i '' -E "s/(CURRENT_PROJECT_VERSION: )\"[^\"]+\"/\1\"${NEW_BUILD}\"/" "${PROJECT_FILE}"

# Stamp CHANGELOG.md header if missing.
if [ -f "${CHANGELOG_FILE}" ]; then
    if grep -q "^## \[${NEW_VERSION}\]" "${CHANGELOG_FILE}"; then
        echo "  CHANGELOG: ## [${NEW_VERSION}] header already present"
    else
        DATE="$(date +%Y-%m-%d)"
        # Insert new header after the first '# Changelog' line.
        awk -v ver="${NEW_VERSION}" -v date="${DATE}" '
            BEGIN { inserted = 0 }
            /^# Changelog/ && !inserted {
                print
                print ""
                print "## [" ver "] — " date
                print ""
                print "- _Add release notes here._"
                inserted = 1
                next
            }
            { print }
        ' "${CHANGELOG_FILE}" > "${CHANGELOG_FILE}.tmp"
        mv "${CHANGELOG_FILE}.tmp" "${CHANGELOG_FILE}"
        echo "  CHANGELOG: stub for ## [${NEW_VERSION}] inserted (edit before release)"
    fi
else
    echo "  CHANGELOG: ${CHANGELOG_FILE} not found — skipping stub"
fi

echo ""
echo "▶ Diff:"
git --no-pager diff -- "${PROJECT_FILE}" "${CHANGELOG_FILE}" || true

if [ "${COMMIT_FLAG}" = "--commit" ]; then
    git add "${PROJECT_FILE}" "${CHANGELOG_FILE}"
    git commit -m "chore: bump version to ${NEW_VERSION}"
    echo ""
    echo "✓ Committed. Edit CHANGELOG.md entries, then: make release"
else
    echo ""
    echo "✓ Files patched (uncommitted). Review CHANGELOG.md, then:"
    echo "    git add ${PROJECT_FILE} ${CHANGELOG_FILE}"
    echo "    git commit -m 'chore: bump version to ${NEW_VERSION}'"
    echo "    make release"
fi
