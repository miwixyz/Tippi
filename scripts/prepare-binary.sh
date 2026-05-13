#!/bin/bash
# Copies whisper-cli + required dylibs from Homebrew into Tippi/Helpers/
# and fixes their @rpath references so they are self-contained inside Tippi.app.
#
# Run once per build machine: make prepare-binary
# The Helpers/ directory is gitignored — regenerate it here.
#
# Requirements: brew install whisper-cpp
# (The release pipeline calls this automatically.)

set -euo pipefail

HELPERS="Tippi/Helpers"
BREW_BIN="/opt/homebrew/bin/whisper-cli"
BREW_GGML_LIB="/opt/homebrew/opt/ggml/lib"
BREW_WHISPER_LIB="/opt/homebrew/opt/whisper-cpp/lib"

# ── Check / install whisper-cpp ──────────────────────────────────────────────

if [ ! -f "${BREW_BIN}" ]; then
    echo "▶ whisper-cpp not found — installing via Homebrew..."
    brew install whisper-cpp
fi

if [ ! -f "${BREW_BIN}" ]; then
    echo "✗ whisper-cli still not found after install. Aborting."
    exit 1
fi

# ── Resolve symlinks to real files ──────────────────────────────────────────

WHISPER_CLI_REAL="$(realpath "${BREW_BIN}")"
LIBWHISPER_REAL="$(realpath "${BREW_WHISPER_LIB}/libwhisper.1.dylib")"
LIBGGML_REAL="$(realpath "${BREW_GGML_LIB}/libggml.0.dylib")"
LIBGGML_BASE_REAL="$(realpath "${BREW_GGML_LIB}/libggml-base.0.dylib")"

echo "▶ Preparing whisper helpers in ${HELPERS}/"
mkdir -p "${HELPERS}"

# ── Copy binaries ────────────────────────────────────────────────────────────

cp "${WHISPER_CLI_REAL}"   "${HELPERS}/whisper-cli"
cp "${LIBWHISPER_REAL}"    "${HELPERS}/libwhisper.1.dylib"
cp "${LIBGGML_REAL}"       "${HELPERS}/libggml.0.dylib"
cp "${LIBGGML_BASE_REAL}"  "${HELPERS}/libggml-base.0.dylib"
chmod +x "${HELPERS}/whisper-cli"

# ── Fix rpaths so helpers are self-contained ────────────────────────────────
#
# Layout inside the final app bundle:
#   Contents/MacOS/whisper-cli           (the executable)
#   Contents/Frameworks/libwhisper.1.dylib
#   Contents/Frameworks/libggml.0.dylib
#   Contents/Frameworks/libggml-base.0.dylib
#
# @executable_path for whisper-cli points to Contents/MacOS/
# → framework dylibs are at @executable_path/../Frameworks/

echo "▶ Fixing rpaths..."

# whisper-cli → libwhisper (was @rpath/libwhisper.1.dylib)
install_name_tool \
    -change "@rpath/libwhisper.1.dylib" \
            "@executable_path/../Frameworks/libwhisper.1.dylib" \
    "${HELPERS}/whisper-cli"

# whisper-cli → libggml (was absolute /opt/homebrew/...)
install_name_tool \
    -change "${BREW_GGML_LIB}/libggml.0.dylib" \
            "@executable_path/../Frameworks/libggml.0.dylib" \
    "${HELPERS}/whisper-cli"

install_name_tool \
    -change "${BREW_GGML_LIB}/libggml-base.0.dylib" \
            "@executable_path/../Frameworks/libggml-base.0.dylib" \
    "${HELPERS}/whisper-cli"

# libwhisper: fix its own ID and its ggml dependencies
install_name_tool \
    -id "@rpath/libwhisper.1.dylib" \
    "${HELPERS}/libwhisper.1.dylib"

install_name_tool \
    -change "${BREW_GGML_LIB}/libggml.0.dylib" \
            "@loader_path/libggml.0.dylib" \
    "${HELPERS}/libwhisper.1.dylib"

install_name_tool \
    -change "${BREW_GGML_LIB}/libggml-base.0.dylib" \
            "@loader_path/libggml-base.0.dylib" \
    "${HELPERS}/libwhisper.1.dylib"

# libggml / libggml-base: fix their own IDs
install_name_tool \
    -id "@rpath/libggml.0.dylib" \
    "${HELPERS}/libggml.0.dylib"

install_name_tool \
    -id "@rpath/libggml-base.0.dylib" \
    "${HELPERS}/libggml-base.0.dylib"

# ── Verify ──────────────────────────────────────────────────────────────────

echo ""
echo "▶ Dependency check:"
otool -L "${HELPERS}/whisper-cli" | grep -v "^${HELPERS}"
echo ""
echo "✓ whisper helpers ready in ${HELPERS}/"
echo "  whisper-cli   $(du -sh "${HELPERS}/whisper-cli"   | cut -f1)"
echo "  libwhisper    $(du -sh "${HELPERS}/libwhisper.1.dylib" | cut -f1)"
echo "  libggml       $(du -sh "${HELPERS}/libggml.0.dylib" | cut -f1)"
echo "  libggml-base  $(du -sh "${HELPERS}/libggml-base.0.dylib" | cut -f1)"
