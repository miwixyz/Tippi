.PHONY: help generate open build clean lint icons release release-dry-run

help:
	@echo "Tippi — Make Targets"
	@echo ""
	@echo "  make generate         Generate Tippi.xcodeproj from project.yml (XcodeGen)"
	@echo "  make open             Generate + open in Xcode"
	@echo "  make build            Build Release configuration (unsigned)"
	@echo "  make clean            Remove generated project and build artifacts"
	@echo "  make icons            Open icons/ folder"
	@echo ""
	@echo "  make release          Build + sign + notarize + DMG (needs release.env)"
	@echo "  make release-dry-run  Show release env without running"

generate:
	@command -v xcodegen >/dev/null 2>&1 || { echo "XcodeGen not found. Install: brew install xcodegen"; exit 1; }
	xcodegen generate

open: generate
	open Tippi.xcodeproj

build: generate
	xcodebuild -project Tippi.xcodeproj -scheme Tippi -configuration Release build

clean:
	rm -rf Tippi.xcodeproj build/ DerivedData/ dist/

icons:
	open icons/

release:
	@./scripts/release.sh

release-dry-run:
	@echo "DEVELOPER_ID:   $${DEVELOPER_ID:-(not set — load from release.env)}"
	@echo "NOTARY_PROFILE: $${NOTARY_PROFILE:-tippi-notary}"
	@echo "VERSION:        $${VERSION:-1.0.0}"
	@test -f release.env && echo "release.env: found" || echo "release.env: NOT found"
