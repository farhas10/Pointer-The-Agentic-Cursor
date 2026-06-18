# Shared schema

The single source of truth for tools (actions the LLM can invoke).

- [`tools.json`](tools.json) — JSON Schema + the canonical tool list.

## Why a single schema

- The **backend** registers these tools with the LLM provider on every
  request and validates tool calls against the input schema.
- The **mac client** has an `ActionExecutor` that maps tool name → real
  implementation (`copy_to_clipboard` → `NSPasteboard`, `click_at` →
  `CGEvent`, etc.).
- The **safety validator** uses the `tier` field to decide which
  confirmation UX to apply.

Both the TypeScript and Swift sides hand-mirror the type definitions
for now. When the schema stabilizes we'll codegen instead.

## Tiers

| Tier          | Confirmation UX                                                                |
| ------------- | ------------------------------------------------------------------------------ |
| `safe`        | Executes immediately; logged to the action history visible in the panel.      |
| `automation`  | 5s countdown; press Enter to run early or Esc to cancel.                      |
| `destructive` | Same 5s countdown; target outlined on screen for ≥ 250 ms before execution.   |
