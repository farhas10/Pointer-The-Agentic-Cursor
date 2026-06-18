# Permissions

Pointer requires three macOS permissions to function. We design the
onboarding to be honest about what each permission does and what
breaks without it.

## Accessibility (required)

**Used for:**
- Reading the UI element under the cursor (role, title, value).
- Inspecting the focused window / app for context.
- Phase 3+: setting field values (`paste_text`, `replace_selection`).
- Phase 4+: clicking and typing on behalf of the user.

**Granted via:** System Settings → Privacy & Security → Accessibility.

**Without it:** The app falls back to "screenshot only" context, which
works but with much less precise targeting (e.g. cannot read text from
a focused field, cannot redact secure fields with confidence).

## Screen Recording (required)

**Used for:**
- Capturing a small region around the cursor for vision context.
- Phase 2+: capturing pasted/marqueed images into a drawer.

**Granted via:** System Settings → Privacy & Security → Screen Recording.

**Without it:** Vision context is unavailable. Text-only AX context
still works for many tasks (Explain, Summarize over selected text).

## Input Monitoring (required for Option+right-click)

**Used for:**
- Listening to global mouse events via `CGEventTap` to detect the
  Option+right-click trigger anywhere on screen.
- Phase 4+: synthesizing input events for the automation tools.

**Granted via:** System Settings → Privacy & Security → Input Monitoring.

**Without it:** Only the secondary hotkey (`Cmd+Shift+Space`) triggers
the panel.

## Onboarding strategy

The first launch presents a three-step onboarding card:

1. Brief intro (what Pointer does, privacy posture).
2. A list of the three permissions with one-line "why" copy and a
   "Grant" button that deep-links into the relevant System Settings
   pane via `x-apple.systempreferences:com.apple.preference.security?Privacy_*`.
3. A live status indicator next to each permission that re-checks on
   `NSApplication.didBecomeActiveNotification`.

Until all three are granted, the menu bar icon shows a yellow dot and
clicking it reopens onboarding.

## Re-checking at runtime

`PermissionsManager` is a small actor that:
- Reads each permission state lazily on demand.
- Caches results for ~1 second to avoid hammering the OS.
- Posts a `permissionsDidChange` notification when something flips.
- Exposes a SwiftUI-friendly `@Observable` snapshot.

If a permission is revoked while the app is running, the affected
features gray out and a banner is shown in the panel.
