.PHONY: help generate open build clean lint icons prepare-binary release release-dry-run bump

help:
	@echo "Tippi — Make Targets"
	@echo ""
	@echo "  make generate         Generate Tippi.xcodeproj from project.yml (XcodeGen)"
	@echo "  make open             Generate + open in Xcode"
	@echo "  make build            Build Release configuration (Developer ID signed — stable TCC identity)"
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
	@if pgrep -x Tippi >/dev/null 2>&1; then echo "Stopping running Tippi before rebuild..."; pkill -x Tippi; sleep 1; fi
	rm -rf build/Build/Products/Release/Tippi.app
	xcodebuild -project Tippi.xcodeproj -scheme Tippi -configuration Release -derivedDataPath ./build build
	codesign --force --deep --sign "Developer ID Application: Michael Wildenauer (LTKJ6Z2VYB)" --entitlements Tippi/Resources/Tippi.entitlements build/Build/Products/Release/Tippi.app

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
