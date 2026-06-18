# Pointer macOS app

Native macOS app written in Swift 6 (SwiftUI + AppKit). The Xcode
project is generated from [`project.yml`](project.yml) via
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Build

```bash
brew install xcodegen
cd mac
xcodegen generate
open Pointer.xcodeproj
```

Then **Product → Run**.

Or from the terminal (builds a signed `.app` and opens it):

```bash
make run
```

Build products go to `~/.cache/pointer-derived` (not `./DerivedData`) so
iCloud Desktop sync does not tag the bundle with `com.apple.provenance`
and break CodeSign.

### Troubleshooting

**CodeSign: "resource fork, Finder information, or similar detritus not
allowed"** — usually iCloud tagging files under `~/Desktop`. Use
`make run` (off-Desktop derived data + pre-sign xattr strip), or move the
repo off Desktop. If it still fails, `make resign-app` re-signs with your
Apple Development identity.

**Microphone permission** — only works when running the signed
`Pointer.app` bundle (not `swift run`). Reset TCC after bundle-id changes:

```bash
killall Pointer 2>/dev/null
tccutil reset Microphone app.pointer.Pointer
make run
```

If `xcodebuild` complains about a missing `IDESimulatorFoundation` plug-in
(`Symbol not found: ...DownloadableAssetType...`), run:

```bash
sudo xcodebuild -runFirstLaunch
```

This installs the system content Xcode 26+ ships separately. Until
that's done, `xcodebuild` from the CLI fails even though Xcode.app
itself opens fine. Building from inside Xcode.app is unaffected.

You can also build and test the code without Xcode at all, using SwiftPM
(this is the most reliable check — it does full Swift 6 strict-concurrency
checking without depending on the Xcode IDE plugins):

```bash
make build    # swift build  — compiles every source file
make test     # swift test   — runs the unit tests
make typecheck  # quick swiftc -typecheck pass (less thorough than build)
```

> There are two build systems here on purpose: `Package.swift` (SwiftPM)
> is for fast, plugin-free compile/test verification, while
> `project.yml` → `Pointer.xcodeproj` is what actually produces the
> runnable, signed `.app` (it carries the Info.plist, entitlements, and
> app-bundle packaging SwiftPM doesn't provide).

On first launch the menu-bar item shows a yellow dot until you grant
Accessibility, Screen Recording, and Input Monitoring. Click it to
reopen the onboarding flow.

## Module map

Each subdirectory under `Sources/Pointer/` is a logical module with a
narrow public surface. Cross-module calls go through small protocol
seams so phases don't leak.

| Folder           | Phase | Purpose |
| ---------------- | ----- | ------- |
| `App/`           | 1     | `@main` entry, app delegate, menu-bar item |
| `Permissions/`   | 1     | Permission checks + onboarding window |
| `Triggers/`      | 1     | Option+right-click `CGEventTap` + global hotkey |
| `Context/`       | 1     | AX extractor + ScreenCaptureKit region capture |
| `Panel/`         | 1     | Floating `NSPanel` + chips-first SwiftUI view |
| `Net/`           | 1     | Backend client + SSE streamer |
| `Models/`        | 1     | Plain shared model types |
| `Cursor/`        | 3     | Cursor halo overlay window |
| `Actions/`       | 3-4   | Tool executor (clipboard / paste / click / type / AS) |
| `Drawer/`        | 2     | Drawer window + item list views |
| `Store/`         | 2     | SQLite + content-addressed blob store + extractors |
| `RAG/`           | 2     | On-device chunking, embeddings, retrieval |

## Backend

The app expects the backend to be reachable at `http://localhost:8787`
during development (configurable in `Net/BackendClient.swift`).
See [`../backend/`](../backend/).

## Why not the App Sandbox?

Phase 4 needs a global `CGEventTap`, synthetic `CGEvent` posting, and
AppleScript bridging — all of which are unavailable to sandboxed apps.
Pointer ships as a notarized direct download. See
[`../docs/threat-model.md`](../docs/threat-model.md).
