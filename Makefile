.PHONY: help generate open build clean lint icons

help:
	@echo "Tippi — Make Targets"
	@echo ""
	@echo "  make generate   Generate Tippi.xcodeproj from project.yml (XcodeGen)"
	@echo "  make open       Generate + open in Xcode"
	@echo "  make build      Build Release configuration via xcodebuild"
	@echo "  make clean      Remove generated project and build artifacts"
	@echo "  make icons      Open icons/ folder (manual placement workflow)"

generate:
	@command -v xcodegen >/dev/null 2>&1 || { echo "XcodeGen not found. Install: brew install xcodegen"; exit 1; }
	xcodegen generate

open: generate
	open Tippi.xcodeproj

build: generate
	xcodebuild -project Tippi.xcodeproj -scheme Tippi -configuration Release build

clean:
	rm -rf Tippi.xcodeproj build/ DerivedData/

icons:
	open icons/
