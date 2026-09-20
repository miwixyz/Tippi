.PHONY: help generate open build clean lint icons prepare-binary release release-dry-run bump

TEAM_ID          := LTKJ6Z2VYB
# Local builds only. scripts/release.sh signs with the Developer ID identity
# for notarised distribution; the two must not be swapped.
# Resolved from the keychain, NOT hardcoded by name.
#
# Apple issues the certificate's Common Name from how the account is registered
# on that machine, so the same developer ID appears under different names:
#   Mac mini : "Apple Development: Michael Wildenauer (54PMA7GFAN)"
#   MacBook  : "Apple Development: miwimail@icloud.com  (54PMA7GFAN)"
# The hardcoded name made `make build` fail on the MacBook with
# "no identity found" *after* BUILD SUCCEEDED — the app was built, only the
# helper signing step died, which reads like a build break but is not one
# (2026-09-20).
#
# The user ID in parentheses is the stable part, so match on that and take the
# SHA-1 hash. Signing by hash is also unambiguous when several certificates
# share a name.
DEV_IDENTITY_USER ?= 54PMA7GFAN
DEV_IDENTITY := $(shell security find-identity -v -p codesigning \
    | grep 'Apple Development' | grep '($(DEV_IDENTITY_USER))' \
    | head -1 | awk '{print $$2}')
DEV_ENTITLEMENTS := build/Tippi.dev.entitlements

help:
	@echo "Tippi — Make Targets"
	@echo ""
	@echo "  make generate         Generate Tippi.xcodeproj from project.yml (XcodeGen)"
	@echo "  make open             Generate + open in Xcode"
	@echo "  make build            Build Release configuration (Apple Development signed — matches the embedded dev profile)"
	@echo "  make test             Run the test suite, then purge the preference domains it leaks"
	@echo "  make clean            Remove generated project and build artifacts"
	@echo "  make icons            Open icons/ folder"
	@echo ""
	@echo "  make prepare-binary   Copy whisper-cli + dylibs from Homebrew, fix rpaths"
	@echo "                        Run once per build machine (needs: brew install whisper-cpp)"
	@echo "  make bump VERSION=X.Y.Z   Patch project.yml + CHANGELOG.md stub (no commit)"
	@echo "  make release          prepare-binary + build + sign + notarize + DMG"
	@echo "  make release-dry-run  Show release env without running"

generate:
	@command -v xcodegen >/dev/null 2>&1 || { echo "XcodeGen not found. Install: brew install xcodegen"; exit 1; }
	xcodegen generate

open: generate
	open Tippi.xcodeproj

build: generate
	@test -n "$(DEV_IDENTITY)" || { \
	  echo "❌ Keine 'Apple Development'-Identität für ($(DEV_IDENTITY_USER)) im Schlüsselbund."; \
	  echo "   Vorhanden:"; security find-identity -v -p codesigning | sed 's/^/   /'; \
	  echo "   → In Xcode anmelden (Settings ▸ Accounts) oder DEV_IDENTITY_USER=<ID> setzen."; \
	  exit 1; }
	@if pgrep -x Tippi >/dev/null 2>&1; then echo "Stopping running Tippi before rebuild..."; pkill -x Tippi; sleep 1; fi
	@test -f Tippi/Helpers/whisper-cli || { echo "Tippi/Helpers/whisper-cli missing — run 'make prepare-binary' first (dictation needs it)"; exit 1; }
	rm -rf build/Build/Products/Release/Tippi.app
	xcodebuild -project Tippi.xcodeproj -scheme Tippi -configuration Release -derivedDataPath ./build build
	cp Tippi/Helpers/whisper-cli build/Build/Products/Release/Tippi.app/Contents/MacOS/whisper-cli
	chmod +x build/Build/Products/Release/Tippi.app/Contents/MacOS/whisper-cli
# Local builds sign with DEV_IDENTITY, not the Developer ID used for
# distribution. The profile Xcode embeds is a *development* profile and lists
# only "Apple Development" certificates; signing the bundle with Developer ID
# leaves amfid unable to match profile to signature, and it kills the app at
# launch with -413 "No matching profile found". That made this target unusable,
# builds moved to Xcode, and Xcode does not copy whisper-cli — which is how the
# installed 2.9.0 ended up without a dictation binary (found 2026-09-14).
# scripts/release.sh keeps Developer ID: notarised distribution is a different
# trust path and must not be changed here.
	codesign --force --options runtime --sign "$(DEV_IDENTITY)" build/Build/Products/Release/Tippi.app/Contents/MacOS/whisper-cli
# `--entitlements <file>` replaces the entitlement set wholesale, dropping the
# application-identifier and team-identifier keys Xcode injects from the
# profile — without them amfid rejects the launch too. They are derived here
# rather than committed to Tippi.entitlements so scripts/release.sh keeps
# seeing the unmodified file. `--options runtime` is required as well: a
# re-sign without it silently drops the hardened runtime flag (0x10000 → 0x0).
# PlistBuddy, not plutil: plutil treats dots in a key as key-path separators,
# so `-insert com.apple.application-identifier` looks for a nested dictionary
# and fails with "Key path not found".
	@plutil -convert xml1 -o "$(DEV_ENTITLEMENTS)" Tippi/Resources/Tippi.entitlements
	@/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $(TEAM_ID).com.tippi.app" "$(DEV_ENTITLEMENTS)" >/dev/null
	@/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $(TEAM_ID)" "$(DEV_ENTITLEMENTS)" >/dev/null
	codesign --force --options runtime --sign "$(DEV_IDENTITY)" --entitlements "$(DEV_ENTITLEMENTS)" build/Build/Products/Release/Tippi.app
# Verify the effect, not the step: a helper that cannot start is exactly the
# failure this target shipped silently before.
	@codesign -d --entitlements - build/Build/Products/Release/Tippi.app/Contents/MacOS/whisper-cli 2>&1 | grep -q icloud \
		&& { echo "✗ whisper-cli still carries iCloud entitlements — it will be killed on launch"; exit 1; } || true
	@build/Build/Products/Release/Tippi.app/Contents/MacOS/whisper-cli --help >/dev/null 2>&1; \
		test $$? -ne 137 || { echo "✗ whisper-cli killed on launch (SIGKILL) — dictation would fail silently"; exit 1; }
	@echo "✓ whisper-cli bundled, signed and able to start"

test: generate
# Warum hier aufgeraeumt wird und nicht im tearDown der Tests (gemessen 2026-09-20):
#
# `ThrowawayDefaults.removeAll()` entfernt die Suite nachweislich — ein eigener
# Messpunkt (`ThrowawayDefaultsTests`) prueft im selben Prozess, dass die Plist
# danach weg ist, und das besteht. Trotzdem lagen nach jedem vollen Lauf exakt so
# viele Dateien in ~/Library/Preferences wie Suiten erzeugt wurden: `cfprefsd`
# haelt die Domains im Cache und schreibt sie nach Prozessende zurueck. Gegen
# einen Daemon, der nach dem Ende des Testprozesses handelt, kann im Testprozess
# nichts gewinnen — der Schritt gehoert dahinter.
#
# Ohne das waren 671 Domains aufgelaufen und `defaults domains` als
# Diagnosewerkzeug unbrauchbar (bei der Notizen-Fehlersuche am 20.09. kam die
# echte App-Domain nach 600 Zeilen Testrauschen).
	xcodebuild test -project Tippi.xcodeproj -scheme Tippi -destination 'platform=macOS'
	@$(MAKE) --no-print-directory purge-test-defaults

purge-test-defaults:
	@before=$$(ls ~/Library/Preferences/ 2>/dev/null | grep -c '^TippiTests' || true); \
	find ~/Library/Preferences -maxdepth 1 -name 'TippiTests.*.plist' -delete 2>/dev/null || true; \
	killall cfprefsd 2>/dev/null || true; \
	sleep 1; \
	after=$$(ls ~/Library/Preferences/ 2>/dev/null | grep -c '^TippiTests' || true); \
	echo "✓ Test-Preference-Domains: $$before → $$after"; \
	test "$$after" -eq 0 || { echo "✗ $$after Domain(s) ueberleben den Daemon-Neustart — von Hand nachsehen"; exit 1; }

clean:
	rm -rf Tippi.xcodeproj build/ DerivedData/ dist/

icons:
	open icons/

prepare-binary:
	@./scripts/prepare-binary.sh

release: prepare-binary
	@./scripts/release.sh

release-dry-run:
	@echo "DEVELOPER_ID:   $${DEVELOPER_ID:-(not set — load from release.env or Keychain)}"
	@echo "NOTARY_PROFILE: $${NOTARY_PROFILE:-tippi-notary}"
	@echo "VERSION:        $$(awk -F'\"' '/MARKETING_VERSION:/ { print $$2; exit }' project.yml) (from project.yml)"
	@test -f release.env && echo "release.env: found" || echo "release.env: NOT found"

bump:
	@if [ -z "$(VERSION)" ]; then \
		echo "Usage: make bump VERSION=X.Y.Z [COMMIT=1]"; \
		exit 2; \
	fi
	@./scripts/bump-version.sh $(VERSION) $(if $(COMMIT),--commit,)
