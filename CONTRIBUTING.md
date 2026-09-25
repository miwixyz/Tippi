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
- Run `make test` before opening a PR. It does three things in order: a concurrency
  lint, the test suite, and a cleanup of the preference domains the tests leave behind
  (verified to reach zero, not assumed)
- Run `make lint` (SwiftLint, strict — needs `brew install swiftlint`). `make release`
  refuses to start on a violation; rules and the reason for every deviation from the
  defaults are in `.swiftlint.yml`

## Running the tests

```bash
make test
```

**Not** `xcodebuild test` directly — that skips both the lint before it and the
cleanup after it.

- **`scripts/concurrency-lint.sh`** flags `MainActor.assumeIsolated` that has no
  evidence of running on the main queue. Accepted evidence is a `queue: .main`
  registration in the ten lines above, or an explicit
  `// concurrency-lint: on-main <reason>` waiver. It exists because 2.11.5 shipped
  exactly that mistake and crashed on launch: `assumeIsolated` does not
  check-and-adapt, it *asserts*, so a wrong assumption is a hard trap. The crash
  path only ran when the app already had a problem to report, so neither the suite
  nor the release pipeline's launch check ever reached it.
- **The cleanup afterwards** removes the `TippiTests.*` preference domains a run
  leaves behind. In-process teardown cannot win here: `cfprefsd` writes the domains
  back from its cache after the test process exits, so the step belongs behind the
  run. Without it they accumulate — 671 had piled up before this was noticed, which
  makes `defaults domains` useless on the machine where you go looking when a
  preference bug is being chased.

## Development setup

```bash
git clone https://github.com/miwixyz/Tippi.git
cd Tippi
brew install xcodegen
make open          # generates Tippi.xcodeproj and opens Xcode
```

Build and run with **⌘R** in Xcode. Unsigned Debug builds work for development but have TCC quirks (Accessibility permission may reset between builds). A signed release build is needed for stable permission testing.

**Testing anything that needs Accessibility** (selection bar, snippets, text replacement) next to an installed Tippi release: run `scripts/devid-testbuild.sh`, then `open /tmp/tippi-devid/export/Tippi.app`. macOS keeps a single Accessibility entry per bundle ID and checks it against the signing certificate. `make build` signs with Apple Development and therefore does **not** satisfy the grant the installed Developer-ID release holds — it runs without the permission. The script produces a Developer-ID build (archive + export + re-sign, no notarization, nothing published) that uses the existing grant as is.

For voice features, build `whisper-cli` once:

```bash
brew install cmake
make prepare-binary   # builds whisper-cli statically and places it in Tippi/Helpers/
```

## Documentation is part of the release

`make release` runs `scripts/docs-release-gate.sh` and **stops** if the docs did
not move with the code. Compared against the previous tag:

| If this changed | then this must have changed |
|---|---|
| a new `.swift` file was added | `ARCHITECTURE.md` lists it |
| `Tippi/UI`, `Tippi/Core`, `Tippi/LLM` | some `settings.help.*Body` other than What's New, in **both** languages |
| `Makefile` or `scripts/` | `CONTRIBUTING.md` |
| `Tippi/UI` or `Tippi/Core` | `README.md` **and** `docs/index.html` |

The gate cannot judge whether the prose is any good — no script can. It checks
the one thing that is checkable: whether the documentation moved at all.

Skipping is allowed, but only out loud:

```bash
RELEASE_DOC_WAIVER="refactor only, no user-visible change" make release
```

The reason is printed into the release output, so a skipped gate leaves a trace
instead of a silence.

**Why it is a gate and not a reminder:** release.sh used to print a polite
"confirm by hand" line on every run. On 2026-09-20 six releases shipped, the
line printed six times, and nothing was confirmed — the in-app Help fell five
versions behind. Run against those releases afterwards, this gate blocks all
three of the ones that needed it and names each gap.

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
| 11 | `generate_appcast` updates `appcast.xml`, Gist updated **and verified against the Gist API** |

### The appcast step needs the `gist` scope — and it is easy to lose

The appcast lives in a GitHub Gist. Updating it requires a token with the
**`gist`** scope, which `gh`'s own keychain login normally has.

**The trap:** an exported `GITHUB_TOKEN` *overrides* that login. If the exported
token only carries `repo, workflow`, the update fails — and GitHub answers with
**404, not 403**, so the message reads like a deleted Gist rather than a missing
permission.

That happened on 2026-09-21 during the 2.12.0 release. The release itself was
complete — signed, notarised, published — while the appcast stayed on 2.11.9.
**Sparkle would have offered the new version to nobody**, and nothing turned red
beyond one line that looked like an infrastructure hiccup.

`release.sh` now checks the scope, falls back to `gh`'s keychain login, and then
reads the Gist back through the **API** to confirm the version actually landed.
The API, not the raw URL: `gist.githubusercontent.com` sits behind a CDN and
serves the previous content for minutes afterwards. The first version of this
check queried the raw URL after two seconds and failed a release that was
perfectly fine — a false alarm is more expensive than no check, because the next
person routes around it.

If you release from a shell that exports `GITHUB_TOKEN`, either give that token
the `gist` scope or unset it for the release:

```bash
env -u GITHUB_TOKEN make release
```

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
