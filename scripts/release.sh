#!/bin/bash
# Tippi release pipeline: build → sign → notarize → DMG → ready for GitHub.
#
# Required env vars (or release.env in repo root):
#   DEVELOPER_ID         e.g. "Developer ID Application: Michael Wildenauer (54PMA7GFAN)"
#   NOTARY_PROFILE       Keychain profile name for notarytool (default: tippi-notary)
#
# VERSION is always read from project.yml MARKETING_VERSION (single source of truth
# since 2026-06-02). Bump it via: ./scripts/bump-version.sh X.Y.Z
#
# Setup notarytool profile once with:
#   xcrun notarytool store-credentials tippi-notary \
#       --apple-id miwimail@icloud.com \
#       --team-id 54PMA7GFAN \
#       --password <app-specific-password>

set -euo pipefail

# release.env (gitignored) optionally provides DEVELOPER_ID / NOTARY_PROFILE.
# It must NOT carry VERSION — project.yml is the single source of truth.
if [ -f release.env ]; then
    # shellcheck disable=SC1091
    set -a; source release.env; set +a
    if [ -n "${VERSION:-}" ]; then
        echo "✗ release.env still defines VERSION. Remove that line — project.yml is the single source of truth."
        echo "  Bump via: ./scripts/bump-version.sh X.Y.Z"
        exit 1
    fi
fi

# ─── Keychain-Fallback (Migration 2026-05-17) ─────────────────────────────────
# Wenn release.env die Vars nicht gesetzt hat: macOS Keychain konsultieren.
# Doku: ~/MWs2ndBrain/04 Ressourcen/KI-Wissen/API-Keys – Inventory.md
KEYS_SH="$HOME/MWs2ndBrain/04 Ressourcen/KI-Wissen/keys.sh"
if [ -x "$KEYS_SH" ]; then
    DEVELOPER_ID="${DEVELOPER_ID:-$(bash "$KEYS_SH" get TIPPI_DEVELOPER_ID 2>/dev/null || true)}"
    NOTARY_PROFILE="${NOTARY_PROFILE:-$(bash "$KEYS_SH" get TIPPI_NOTARY_PROFILE 2>/dev/null || true)}"
fi

VERSION="$(awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' project.yml)"
APP_NAME="Tippi"
BUNDLE_ID="com.tippi.app"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR="./build/Build/Products/Release"
DIST_DIR="./dist"
DEVELOPER_ID="${DEVELOPER_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-tippi-notary}"

if [ -z "${DEVELOPER_ID}" ]; then
    echo "✗ DEVELOPER_ID not set. Add to release.env, export it, or store in Keychain (TIPPI_DEVELOPER_ID)."
    echo "  Example: DEVELOPER_ID='Developer ID Application: Michael Wildenauer (54PMA7GFAN)'"
    exit 1
fi
if [ -z "${VERSION}" ]; then
    echo "✗ MARKETING_VERSION could not be read from project.yml."
    echo "  Bump via: ./scripts/bump-version.sh X.Y.Z"
    exit 1
fi

echo "▶ Tippi release pipeline"
echo "  Version:     ${VERSION}"
echo "  Signing:     ${DEVELOPER_ID}"
echo "  Notary:      ${NOTARY_PROFILE}"
# BUILD_NUMBER is set later (after git rev-list), printed during build step
echo ""

# 0. Pre-release sanity: docs ↔ code drift check.
# Catches features that were shipped in code but never reflected in user-facing
# help texts. Fails the release if any provider or built-in prompt is mentioned
# in code but missing from settings.help.apiBody / About-Tab features in either
# Localizable.strings file.
echo "▶ [0/7] Drift check: code ↔ Help texts..."
LROUTER="Tippi/LLM/LLMRouter.swift"
EN_STRINGS="Tippi/Resources/en.lproj/Localizable.strings"
DE_STRINGS="Tippi/Resources/de.lproj/Localizable.strings"
DRIFT_ERRORS=0

# Extract provider names: e.g. "OpenAIProvider()" → "OpenAI"
PROVIDERS=$(grep -oE '\b[A-Z][A-Za-z]+Provider\(\)' "${LROUTER}" | sed 's/Provider()//')
for p in ${PROVIDERS}; do
    case "${p}" in
        Anthropic) needle_en="Anthropic"; needle_de="Anthropic";;
        Mistral)   needle_en="Mistral";   needle_de="Mistral";;
        OpenAI)    needle_en="OpenAI";    needle_de="OpenAI";;
        Gemini)    needle_en="Gemini";    needle_de="Gemini";;
        Ollama)    needle_en="Ollama";    needle_de="Ollama";;
        MLX)       needle_en="MLX";       needle_de="MLX";;
        *)         needle_en="${p}";      needle_de="${p}";;
    esac
    grep -q "settings.help.apiBody.*${needle_en}" "${EN_STRINGS}" || {
        echo "  ✗ Provider '${p}' not mentioned in EN settings.help.apiBody"; DRIFT_ERRORS=1; }
    grep -q "settings.help.apiBody.*${needle_de}" "${DE_STRINGS}" || {
        echo "  ✗ Provider '${p}' not mentioned in DE settings.help.apiBody"; DRIFT_ERRORS=1; }
done

# About-Tab feature2: should mention the actual provider count.
ACTUAL_COUNT=$(echo "${PROVIDERS}" | wc -w | tr -d ' ')
if ! grep -q "settings.about.feature2.*${ACTUAL_COUNT}" "${EN_STRINGS}"; then
    echo "  ✗ EN settings.about.feature2 doesn't mention the current provider count (${ACTUAL_COUNT})"
    DRIFT_ERRORS=1
fi
if ! grep -q "settings.about.feature2.*${ACTUAL_COUNT}" "${DE_STRINGS}"; then
    echo "  ✗ DE settings.about.feature2 doesn't mention the current provider count (${ACTUAL_COUNT})"
    DRIFT_ERRORS=1
fi

if [ "${DRIFT_ERRORS}" -ne 0 ]; then
    echo ""
    echo "✗ Help texts are out of date — refusing to release with stale documentation."
    echo "  Update Tippi/Resources/{en,de}.lproj/Localizable.strings, then retry."
    exit 1
fi
echo "  ✓ Help texts match shipped code (${ACTUAL_COUNT} providers, both languages)"

# 1. Clean previous build
rm -rf build dist
mkdir -p "${DIST_DIR}"

# 2. Generate Xcode project
echo "▶ [1/7] Generating Xcode project..."
xcodegen generate >/dev/null

# 3. Build Release
# Build number = git commit count — monotonically increasing, no manual tracking needed.
BUILD_NUMBER="$(git rev-list --count HEAD)"
echo "▶ [2/7] Building Release with hardened runtime (build ${BUILD_NUMBER})..."
xcodebuild \
    -project Tippi.xcodeproj \
    -scheme Tippi \
    -configuration Release \
    -derivedDataPath ./build \
    MARKETING_VERSION="${VERSION}" \
    CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="${DEVELOPER_ID}" \
    OTHER_CODE_SIGN_FLAGS="--options=runtime --timestamp" \
    build >/dev/null

APP_PATH="${BUILD_DIR}/${APP_BUNDLE}"
if [ ! -d "${APP_PATH}" ]; then
    echo "✗ Build failed — ${APP_PATH} not found"; exit 1
fi

# 4a. Inject whisper-cli into bundle (static binary — no separate dylibs needed)
echo "▶ [3/7] Injecting whisper-cli into bundle..."
HELPERS_SRC="./Tippi/Helpers"
if [ ! -f "${HELPERS_SRC}/whisper-cli" ]; then
    echo "✗ ${HELPERS_SRC}/whisper-cli not found."
    echo "  Run: make prepare-binary"
    exit 1
fi
cp "${HELPERS_SRC}/whisper-cli" "${APP_PATH}/Contents/MacOS/whisper-cli"
chmod +x "${APP_PATH}/Contents/MacOS/whisper-cli"

# 4b. Re-sign: whisper-cli + Sparkle (inside → out), then outer app
echo "▶ [3/7] Re-signing app with explicit entitlements + verifying..."
SPARKLE_FW="${APP_PATH}/Contents/Frameworks/Sparkle.framework/Versions/B"

# Sign whisper-cli binary
codesign --force --options runtime --timestamp --sign "${DEVELOPER_ID}" \
    "${APP_PATH}/Contents/MacOS/whisper-cli"

# Sign Sparkle executables
for bin in \
    "${SPARKLE_FW}/XPCServices/Installer.xpc/Contents/MacOS/Installer" \
    "${SPARKLE_FW}/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" \
    "${SPARKLE_FW}/Autoupdate" \
    "${SPARKLE_FW}/Updater.app/Contents/MacOS/Updater"; do
    [ -f "$bin" ] && codesign --force --options runtime --timestamp --sign "${DEVELOPER_ID}" "$bin"
done

# Sign Sparkle bundles
for bundle in \
    "${SPARKLE_FW}/XPCServices/Installer.xpc" \
    "${SPARKLE_FW}/XPCServices/Downloader.xpc" \
    "${SPARKLE_FW}/Updater.app"; do
    [ -d "$bundle" ] && codesign --force --options runtime --timestamp --sign "${DEVELOPER_ID}" "$bundle"
done

# Sign Sparkle framework
codesign --force --options runtime --timestamp --sign "${DEVELOPER_ID}" \
    "${APP_PATH}/Contents/Frameworks/Sparkle.framework"

# Sign outer app with our entitlements
codesign --force --options runtime --timestamp \
    --entitlements Tippi/Resources/Tippi.entitlements \
    --sign "${DEVELOPER_ID}" \
    "${APP_PATH}"
codesign --verify --deep --strict "${APP_PATH}" && echo "  ✓ Signature valid"

# 5. Create DMG
echo "▶ [4/7] Creating DMG..."
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
STAGING="${DIST_DIR}/dmg-staging"
rm -rf "${STAGING}"
mkdir -p "${STAGING}"
cp -R "${APP_PATH}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

hdiutil create -volname "Tippi ${VERSION}" \
    -srcfolder "${STAGING}" \
    -ov -format UDZO \
    "${DMG_PATH}" >/dev/null

rm -rf "${STAGING}"

# 6. Sign DMG
echo "▶ [5/7] Signing DMG..."
codesign --sign "${DEVELOPER_ID}" --timestamp "${DMG_PATH}"

# 7. Notarize
echo "▶ [6/7] Submitting to Apple notary service (this can take a few minutes)..."
xcrun notarytool submit "${DMG_PATH}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait \
    --output-format json > "${DIST_DIR}/notarization.json"

STATUS="$(/usr/bin/plutil -extract status raw -o - "${DIST_DIR}/notarization.json")"
if [ "${STATUS}" != "Accepted" ]; then
    echo "✗ Notarization status: ${STATUS}"
    cat "${DIST_DIR}/notarization.json"
    exit 1
fi
echo "  ✓ Notarization accepted"

# 8. Staple
echo "▶ [7/7] Stapling notarization ticket..."
xcrun stapler staple "${DMG_PATH}" >/dev/null
SPCTL_OUTPUT="$(spctl --assess --type open --context context:primary-signature -v "${DMG_PATH}" 2>&1)"
echo "${SPCTL_OUTPUT}" | awk 'NR <= 2 { print }'

# 9. GitHub Release — upload DMG first so the download URL exists for the appcast
echo "▶ [8/9] Creating GitHub release..."
GH_RELEASE_URL="https://github.com/miwixyz/Tippi/releases/download/v${VERSION}"
# Extract release notes for this version from CHANGELOG.md
# (macOS BSD head has no -n -1 support; use awk to skip header + stop at next entry)
RELEASE_NOTES="$(awk "/^## \[${VERSION}\]/{found=1;next} found && /^## \[/{exit} found{print}" CHANGELOG.md)"
if gh release view "v${VERSION}" >/dev/null 2>&1; then
    gh release upload "v${VERSION}" "${DMG_PATH}" --clobber
    echo "  ✓ GitHub Release v${VERSION} aktualisiert"
else
    gh release create "v${VERSION}" "${DMG_PATH}" \
        --title "Tippi ${VERSION}" \
        --notes "${RELEASE_NOTES}"
    echo "  ✓ GitHub Release v${VERSION} erstellt"
fi
gh release view "v${VERSION}" >/dev/null

# 10. Generate appcast.xml — DMGs are hosted on GitHub Releases, not Gist
echo "▶ [9/9] Generating appcast.xml..."
APPCAST_TOOL="${HOME}/Developer/sparkle-tools/bin/generate_appcast"
if [ -f "${APPCAST_TOOL}" ]; then
    "${APPCAST_TOOL}" "${DIST_DIR}" \
        --download-url-prefix "${GH_RELEASE_URL}/" \
        -o appcast.xml 2>/dev/null
    gh gist edit 595ce79e698bb6a98008dc061f1f4a78 appcast.xml
    echo "  ✓ appcast.xml generiert und Gist aktualisiert"
else
    echo "  ⚠ Sparkle tools nicht gefunden unter ${APPCAST_TOOL}"
    echo "    Setup: siehe docs/HANDOVER.md → Sparkle"
fi

# 11. Final report
echo ""
echo "✓ Release complete"
echo "  DMG:  ${DMG_PATH}"
echo "  Size: $(du -h "${DMG_PATH}" | cut -f1)"
echo ""
echo "Next steps:"
echo "  1. git add appcast.xml && git commit -m 'release: v${VERSION}' && git push"
