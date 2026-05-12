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
echo ""

# 1. Clean previous build
rm -rf build dist
mkdir -p "${DIST_DIR}"

# 2. Generate Xcode project
echo "▶ [1/7] Generating Xcode project..."
xcodegen generate >/dev/null

# 3. Build Release
echo "▶ [2/7] Building Release with hardened runtime..."
xcodebuild \
    -project Tippi.xcodeproj \
    -scheme Tippi \
    -configuration Release \
    -derivedDataPath ./build \
    MARKETING_VERSION="${VERSION}" \
    CURRENT_PROJECT_VERSION="1" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="${DEVELOPER_ID}" \
    OTHER_CODE_SIGN_FLAGS="--options=runtime --timestamp" \
    build >/dev/null

APP_PATH="${BUILD_DIR}/${APP_BUNDLE}"
if [ ! -d "${APP_PATH}" ]; then
    echo "✗ Build failed — ${APP_PATH} not found"; exit 1
fi

# 4. Re-sign explicitly with our entitlements file to make sure get-task-allow=false
echo "▶ [3/7] Re-signing app with explicit entitlements + verifying..."
codesign --force --options runtime --timestamp \
    --entitlements Tippi/Resources/Tippi.entitlements \
    --sign "${DEVELOPER_ID}" \
    "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}" 2>&1 | head -5

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

# 9. Final report
echo ""
echo "✓ Release complete"
echo "  DMG:  ${DMG_PATH}"
echo "  Size: $(du -h "${DMG_PATH}" | cut -f1)"
echo ""
echo "Next: upload to GitHub release with:"
echo "  gh release create v${VERSION} ${DMG_PATH} --title 'Tippi ${VERSION}' --notes-file CHANGELOG.md"
