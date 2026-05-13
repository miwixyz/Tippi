#!/bin/bash
# Builds whisper-cli from source with statically embedded backends.
# No Homebrew whisper-cpp needed; no .so plugin files required at runtime.
#
# Run once per build machine: make prepare-binary
# The Helpers/ directory is gitignored — regenerate it here.
#
# Requirements: cmake (brew install cmake), git, Xcode Command Line Tools
# (The release pipeline calls this automatically.)

set -euo pipefail

HELPERS="Tippi/Helpers"
SRC_DIR="${HELPERS}/whisper.cpp"
BUILD_DIR="${HELPERS}/whisper-build"
WHISPER_VERSION="v1.7.4"   # last stable release before ggml plugin split
WHISPER_REPO="https://github.com/ggerganov/whisper.cpp"

# ── Check requirements ────────────────────────────────────────────────────────

if ! command -v cmake >/dev/null 2>&1; then
    echo "✗ cmake not found. Install: brew install cmake"
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "✗ git not found."
    exit 1
fi

# ── Clone source (once) ───────────────────────────────────────────────────────

if [ ! -d "${SRC_DIR}/.git" ]; then
    echo "▶ Cloning whisper.cpp ${WHISPER_VERSION}..."
    mkdir -p "${HELPERS}"
    git clone --depth 1 --branch "${WHISPER_VERSION}" "${WHISPER_REPO}" "${SRC_DIR}"
else
    echo "▶ Using existing whisper.cpp source in ${SRC_DIR}/"
fi

# ── Configure ─────────────────────────────────────────────────────────────────

echo "▶ Configuring cmake (static, Metal embedded, no plugin backends)..."
cmake -S "${SRC_DIR}" -B "${BUILD_DIR}" -Wno-dev \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DGGML_BACKEND_DL=OFF \
    -DGGML_BLAS=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=ON \
    -DWHISPER_BUILD_SERVER=OFF \
    2>/dev/null

# ── Build ─────────────────────────────────────────────────────────────────────

NCPU="$(sysctl -n hw.ncpu)"
echo "▶ Building whisper-cli (${NCPU} cores) — this takes ~2 min on first run..."
cmake --build "${BUILD_DIR}" \
    --config Release \
    -j"${NCPU}" \
    --target whisper-cli

# ── Install ────────────────────────────────────────────────────────────────────

chmod -R u+w "${HELPERS}" 2>/dev/null || true
mkdir -p "${HELPERS}"
cp "${BUILD_DIR}/bin/whisper-cli" "${HELPERS}/whisper-cli"
chmod 755 "${HELPERS}/whisper-cli"

# ── Verify ─────────────────────────────────────────────────────────────────────

echo ""
echo "▶ Dependency check (should show only system frameworks):"
otool -L "${HELPERS}/whisper-cli" | grep -v "^${HELPERS}"
echo ""
BINARY_SIZE="$(du -sh "${HELPERS}/whisper-cli" | cut -f1)"
echo "✓ whisper-cli (static) ready in ${HELPERS}/  [${BINARY_SIZE}]"
