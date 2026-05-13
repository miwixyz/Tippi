#!/bin/bash
# Tippi release pipeline: build → sign → notarize → DMG → ready for GitHub.
#
# Required env vars (or release.env in repo root):
#   DEVELOPER_ID         e.g. "Developer ID Application: Michael Wildenauer (54PMA7GFAN)"
#   NOTARY_PROFILE       Keychain profile name for notarytool (default: tippi-notary)
#   VERSION              Release version tag, e.g. 1.0.0 (default: read from project.yml)
#
# Setup notarytool profile once with:
#   xcrun notarytool store-credentials tippi-notary \
#       --apple-id miwimail@icloud.com \
#       --team-id 54PMA7GFAN \
#       --password <app-specific-password>

set -euo pipefail

# Load env from file if present
if [ -f release.env ]; then
    # shellcheck disable=SC1091
    set -a; source release.env; set +a
fi

VERSION="${VERSION:-1.0.0}"
APP_NAME="Tippi"
BUNDLE_ID="com.tippi.app"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR="./build/Build/Products/Release"
DIST_DIR="./dist"
DEVELOPER_ID="${DEVELOPER_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-tippi-notary}"

if [ -z "${DEVELOPER_ID}" ]; then
    echo "✗ DEVELOPER_ID not set. Add to release.env or export it."
    echo "  Example: DEVELOPER_ID='Developer ID Application: Michael Wildenauer (54PMA7GFAN)'"
    exit 1
fi

echo "▶ Tippi release pipeline"
echo "  Version:     ${VERSION}"
echo "  Signing:     ${DEVELOPER_ID}"
echo "  Notary:      ${NOTARY_PROFILE}"
# BUILD_NUMBER is set later (after git rev-list), printed during build step
echo ""

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

STATUS=$(grep -o '"status":"[^"]*"' "${DIST_DIR}/notarization.json" | head -1 | cut -d'"' -f4)
if [ "${STATUS}" != "Accepted" ]; then
    echo "✗ Notarization status: ${STATUS}"
    cat "${DIST_DIR}/notarization.json"
    exit 1
fi
echo "  ✓ Notarization accepted"

# 8. Staple
echo "▶ [7/7] Stapling notarization ticket..."
xcrun stapler staple "${DMG_PATH}" >/dev/null
spctl --assess --type open --context context:primary-signature -v "${DMG_PATH}" 2>&1 | head -2

# 9. GitHub Release — upload DMG first so the download URL exists for the appcast
echo "▶ [8/9] Creating GitHub release..."
GH_RELEASE_URL="https://github.com/miwixyz/Tippi/releases/download/v${VERSION}"
# Extract release notes for this version from CHANGELOG.md
# (macOS BSD head has no -n -1 support; use awk to skip header + stop at next entry)
RELEASE_NOTES="$(awk "/^## \[${VERSION}\]/{found=1;next} found && /^## \[/{exit} found{print}" CHANGELOG.md)"
gh release create "v${VERSION}" "${DMG_PATH}" \
    --title "Tippi ${VERSION}" \
    --notes "${RELEASE_NOTES}" 2>/dev/null \
    && echo "  ✓ GitHub Release v${VERSION} erstellt" \
    || echo "  ⚠ GitHub Release existiert bereits oder Fehler — appcast wird trotzdem generiert"

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
