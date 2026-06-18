# Threat model

A short, deliberately practical threat model for Pointer. Updated as
phases ship.

## Assets

1. **Screen content** — anything captured by ScreenCaptureKit on a trigger.
2. **AX snapshots** — element-under-cursor data, often containing user text.
3. **Drawer content** — files, images, snippets, URLs the user has explicitly added.
4. **Embeddings** — local vectors derived from drawer content.
5. **User identity** — Sign-in-with-Apple email, Stripe customer ID.
6. **API keys** — Anthropic / OpenAI keys held by the backend, *not* the client.

## Adversaries

- **Curious onlooker** — someone shoulder-surfing while Pointer fires.
- **Malicious local app** — another app running as the user that wants
  to read Pointer's local data or hijack its event tap.
- **Compromised network** — MITM between client and backend.
- **Compromised backend host** — attacker on the server side.
- **Compromised LLM provider** — provider mis-uses or leaks request data.

## Mitigations by adversary

### Curious onlooker
- Panel auto-dismisses on focus loss after 8s.
- Halo never shows answer content; only state.
- Drawer windows close on `Cmd+W` and require explicit reopen.

### Malicious local app
- App is **not sandboxed** by necessity, so we cannot rely on the App
  Sandbox to isolate our data. Mitigations:
  - Drawer SQLite + blobs stored under
    `~/Library/Application Support/Pointer/` with `0700` perms.
  - No long-lived bearer token on disk; auth uses a hardware-backed
    secure-enclave key for token signing where possible.
  - CGEventTap is owned by a single coordinator and refuses re-creation;
    duplicate taps from another process do not affect us, but they would
    affect the user globally — we cannot defend against the user's own
    decision to install hostile software.

### Compromised network
- All backend traffic is HTTPS with cert pinning to a small set of issuers.
- Auth tokens are short-lived (15 min), refreshed via Sign-in-with-Apple.

### Compromised backend host
- Request bodies are **not persisted**. Logs contain only metric-level
  data (latency, status, model, token counts) and the user account ID.
- Streaming responses pass through; nothing buffered to disk.
- Stripe and account metadata are stored in Postgres with row-level
  security, encrypted at rest by the provider.

### Compromised LLM provider
- We pass content through with no training-on-data flag enabled.
- Users with regulatory needs can opt into BYOK (planned post-Phase 1)
  to route through their own keys.

## Specific risks worth calling out

- **AX leakage**: AX values can include sensitive content (notes,
  passwords typed into custom non-`AXSecureTextField` widgets). The
  client redacts on a best-effort basis using role + heuristics; we
  document this clearly so users understand "Option+right-click on a
  password field" is a deliberate user action, not magic safety.
- **Screenshot leakage**: a 768 px region capture can include neighboring
  UI. We crop tightly around the click point and hash + cache identical
  screenshots so the same surface isn't re-uploaded on rapid retries.
- **Automation safety (Phase 4)**: full-automation tools are gated by
  a confirmation UX that shows the target outline on screen for
  ≥ 250 ms before any synthetic event. `Esc` cancels the entire queue.
  Password fields and Stripe iframes are blocked by the backend
  validator; cross-app actions require an elevated confirm step.

## Out of scope (acknowledged)

- Defending against a fully privileged attacker on the user's Mac.
- Defending against the user themselves intentionally trying to leak data.
- Side-channel attacks on the LLM (prompt injection from the page
  content). Mitigation is policy-level (system prompt structure,
  refusal rules) and is iterated on.
