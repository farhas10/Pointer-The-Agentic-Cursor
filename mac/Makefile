## Convenience targets for the macOS app.
##
## Most day-to-day work happens in Xcode after `make project`, but
## `make typecheck` is useful for quick verification without a full
## build (and works around the Xcode 26.5 plug-in issue described in
## README.md).

SDK     := $(shell xcrun -sdk macosx --show-sdk-path)
TARGET  := arm64-apple-macos14
SOURCES := $(shell find Sources/Pointer -name '*.swift')

# Keep build products off Desktop/iCloud — provenance xattrs break CodeSign there.
DERIVED := $(HOME)/.cache/pointer-derived
APP     := $(DERIVED)/Build/Products/Debug/Pointer.app
ENTITLEMENTS := $(DERIVED)/Build/Intermediates.noindex/Pointer.build/Debug/Pointer.build/Pointer.app.xcent
SIGN_ID := $(shell security find-identity -v -p codesigning 2>/dev/null | grep 'Apple Development' | head -1 | sed -E 's/.*"(.+)"$$/\1/')
export COPYFILE_DISABLE := 1

.PHONY: all project build app resign-app run test typecheck clean strip-provenance-xattrs

all: build

project:
	xcodegen generate
	chmod +x Scripts/strip-xattrs.sh

## `swift build` is the reliable compile gate: it uses the same toolchain
## as Xcode with full Swift 6 strict-concurrency checking, but does NOT
## depend on the Xcode IDE plugins (which can fail to load on CI / fresh
## installs). Prefer this over `typecheck` for catching data-race errors.
build:
	swift build

## Strip iCloud/Finder xattrs from project sources before CodeSign.
## Skip `.build/` — SwiftPM checkouts are read-only and xattr fails there.
strip-provenance-xattrs:
	xattr -cr Sources 2>/dev/null || true
	xattr -cr Scripts 2>/dev/null || true
	xattr -cr Pointer.xcodeproj 2>/dev/null || true
	xattr -cr project.yml Package.swift Makefile 2>/dev/null || true
	xattr -cr $(DERIVED) 2>/dev/null || true

## Build the signed .app bundle (required for mic + other TCC permissions).
app: project strip-provenance-xattrs
	xcodebuild -scheme Pointer -configuration Debug -derivedDataPath $(DERIVED) build \
		|| $(MAKE) resign-app
	@$(MAKE) verify-app

verify-app:
	@test -d "$(APP)" || (echo "Missing $(APP)" && exit 1)
	@/usr/libexec/PlistBuddy -c 'Print :NSMicrophoneUsageDescription' "$(APP)/Contents/Info.plist" >/dev/null \
		|| (echo "ERROR: built app is missing NSMicrophoneUsageDescription" && exit 1)
	@echo "OK: NSMicrophoneUsageDescription present in $(APP)"

## Recover from CodeSign failures caused by Finder/iCloud metadata.
resign-app:
	@test -d "$(APP)" || (echo "Build failed before $(APP) was created." && exit 1)
	xattr -cr "$(APP)"
	dot_clean -m "$(APP)" 2>/dev/null || true
	xattr -d com.apple.FinderInfo "$(APP)" 2>/dev/null || true
	xattr -d com.apple.fileprovider.fpfs#P "$(APP)" 2>/dev/null || true
	xattr -cr "$(APP)"
	@if [ -n "$(SIGN_ID)" ] && [ -f "$(ENTITLEMENTS)" ]; then \
		codesign --force --sign "$(SIGN_ID)" --entitlements "$(ENTITLEMENTS)" --deep "$(APP)"; \
		echo "Re-signed $(APP) with $(SIGN_ID)"; \
	else \
		codesign --force --sign - --deep "$(APP)"; \
		echo "Re-signed $(APP) (adhoc — mic TCC may not work until xcodebuild signs)"; \
	fi

## Build and launch Pointer.app.
run: app
	open "$(APP)"

test:
	swift test

## Lightweight check (faster, but less thorough than `build` for
## region-isolation / sendability diagnostics — kept for quick passes).
typecheck:
	xcrun swiftc -typecheck \
	  -sdk "$(SDK)" \
	  -target $(TARGET) \
	  -parse-as-library \
	  -swift-version 6 \
	  -strict-concurrency=complete \
	  $(SOURCES)

clean:
	rm -rf Pointer.xcodeproj DerivedData "$(DERIVED)" .build
