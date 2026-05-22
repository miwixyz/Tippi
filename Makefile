.PHONY: help generate open build clean lint icons prepare-binary release release-dry-run

help:
	@echo "Tippi — Make Targets"
	@echo ""
	@echo "  make generate         Generate Tippi.xcodeproj from project.yml (XcodeGen)"
	@echo "  make open             Generate + open in Xcode"
	@echo "  make build            Build Release configuration (local ad-hoc signed)"
	@echo "  make clean            Remove generated project and build artifacts"
	@echo "  make icons            Open icons/ folder"
	@echo ""
	@echo "  make prepare-binary   Copy whisper-cli + dylibs from Homebrew, fix rpaths"
	@echo "                        Run once per build machine (needs: brew install whisper-cpp)"
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
	codesign --force --deep --sign - --entitlements Tippi/Resources/Tippi.entitlements build/Build/Products/Release/Tippi.app

clean:
	rm -rf Tippi.xcodeproj build/ DerivedData/ dist/

icons:
	open icons/

prepare-binary:
	@./scripts/prepare-binary.sh

release: prepare-binary
	@./scripts/release.sh

release-dry-run:
	@echo "DEVELOPER_ID:   $${DEVELOPER_ID:-(not set — load from release.env)}"
	@echo "NOTARY_PROFILE: $${NOTARY_PROFILE:-tippi-notary}"
	@echo "VERSION:        $${VERSION:-$$(awk -F'\"' '/MARKETING_VERSION:/ { print $$2; exit }' project.yml)}"
	@test -f release.env && echo "release.env: found" || echo "release.env: NOT found"
