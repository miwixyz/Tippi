# Contributing to Tippi

## Bug reports & feature requests

Open a [GitHub issue](https://github.com/miwixyz/Tippi/issues). For bugs, include:

- macOS version
- Tippi version (menu bar icon → Settings → About)
- Steps to reproduce
- What you expected vs. what happened

## Pull requests

- Keep changes focused — one fix or feature per PR
- Match the existing Swift style (SwiftUI-first, no third-party UI dependencies)
- Test with a signed build if your change touches text capture, hotkeys, or permissions

## Development setup

```bash
git clone https://github.com/miwixyz/Tippi.git
cd Tippi
brew install xcodegen
make open          # generates Tippi.xcodeproj and opens Xcode
```

Build and run with **⌘R** in Xcode. Unsigned Debug builds work for development but have TCC quirks (Accessibility permission may reset between builds). A signed release build is needed for stable permission testing.

For voice features, build `whisper-cli` once:

```bash
brew install cmake
make prepare-binary   # builds whisper-cli statically and places it in Tippi/Helpers/
```

## Building a signed release

A Developer ID–signed and Apple-notarized DMG is required for stable distribution.

### One-time setup

1. **Apple Developer Program** membership ($99/year)

2. **Developer ID Application certificate** — create at [developer.apple.com](https://developer.apple.com) and install in Keychain

3. **App-specific password** — create at [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords

4. **notarytool credentials profile:**

   ```bash
   xcrun notarytool store-credentials tippi-notary \
       --apple-id you@example.com \
       --team-id YOUR_TEAM_ID \
       --password "xxxx-xxxx-xxxx-xxxx"
   ```

5. **Sparkle CLI tools** — download `Sparkle-X.Y.Z.tar.xz` from [sparkle-project/Sparkle releases](https://github.com/sparkle-project/Sparkle/releases), extract, copy `bin/generate_appcast` to `~/Developer/sparkle-tools/bin/`

6. **`release.env`** — copy from `release.env.example` and fill in your values:

   ```bash
   DEVELOPER_ID="Developer ID Application: Your Name (YOUR_TEAM_ID)"
   NOTARY_PROFILE="tippi-notary"
   VERSION="1.0.0"
   ```

7. **If you forked the repo**, update the Gist ID and GitHub repo slug in `scripts/release.sh` (lines near the `gh gist edit` and `gh release create` calls).

### Running the pipeline

```bash
make release
```

`scripts/release.sh` runs the full pipeline:

| Step | What happens |
|------|-------------|
| 1 | `make prepare-binary` — builds static `whisper-cli` |
| 2 | `xcodegen generate` — creates `Tippi.xcodeproj` |
| 3 | `xcodebuild` Release — hardened runtime, Developer ID, build number from `git rev-list --count HEAD` |
| 4 | `whisper-cli` injected into `Contents/MacOS/` |
| 5 | Sparkle nested signing (XPC binaries → bundles → framework → app, inside-out) |
| 6 | DMG created via `hdiutil` |
| 7 | DMG signed |
| 8 | Apple notarization via `xcrun notarytool submit --wait` (~3–10 min) |
| 9 | Notarization ticket stapled |
| 10 | GitHub Release created, DMG uploaded |
| 11 | `generate_appcast` updates `appcast.xml`, Gist updated |

After the script completes:

```bash
git add appcast.xml && git commit -m "release: vX.Y.Z" && git push
```

Output: `dist/Tippi-<version>.dmg` — signed, notarized, stapled, ready to ship.

### Version bumping

1. Set `VERSION="x.y.z"` in `release.env`
2. Add a `## [x.y.z]` entry to `CHANGELOG.md`
3. Run `make release`

The build number (`CFBundleVersion`) is derived automatically from `git rev-list --count HEAD` — no manual tracking needed. Sparkle compares build numbers (not marketing versions) to decide whether to offer an update.
