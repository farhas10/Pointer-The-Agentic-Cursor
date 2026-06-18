# Backend

The Pointer managed backend. A small TypeScript / Hono service that
proxies user requests to an LLM provider and streams answers back over
SSE.

## Run locally

```bash
pnpm install
cp .env.example .env
# Optional: paste your ANTHROPIC_API_KEY into .env. Without it, the
# server runs in MOCK mode and streams canned responses — perfect for
# client development.
pnpm dev
```

The service listens on `http://localhost:8787` by default.

## Endpoints

### `GET /healthz`
Returns `{ ok: true, provider: "anthropic" | "mock" }`.

### `POST /v1/agent/ask`

Streams a server-sent-events response containing tokens and (later)
tool call events. See [`src/routes/agent.ts`](src/routes/agent.ts) for
the request shape.

```jsonc
// Request
{
  "prompt": "What is this?",
  "chip_intent": "explain",                // optional, from chips engine
  "ax_snapshot": { /* see types.ts */ },
  "image_b64": "...",                      // optional, jpeg/png
  "app_context": { "bundle_id": "com.apple.Safari", "title": "Linear pricing" }
}

// Response (text/event-stream)
event: token
data: {"text":"Linear's "}

event: token
data: {"text":"Standard "}

event: done
data: {"finish_reason":"stop","usage":{"input_tokens":312,"output_tokens":48}}
```

### `POST /v1/drawer/query` (Phase 2)

Same SSE shape, but accepts a list of items (text chunks + raw images)
retrieved on-device by the client and asks the LLM across them.

## Layout

```
src/
  index.ts            Entry — boots the Hono server.
  server.ts           Composes routes + middleware into a Hono app.
  config.ts           Typed env config (loaded once at boot).
  types.ts            Public request/response types.

  routes/             One file per endpoint group.
  llm/                Provider interface + Anthropic + Mock + registry.
  safety/             Tool-call validator and request redaction.
  middleware/         Auth, rate limit, request logging.
```

## Provider model

`LLMProvider` is a minimal interface (see `src/llm/provider.ts`).
`AnthropicProvider` and `MockProvider` both implement it. The registry
picks one at boot based on `ANTHROPIC_API_KEY`.

This keeps the service trivially testable and lets us add fallback
providers (OpenAI, local) without changing routes.

## Tests

```bash
pnpm test
```

Tests live in `test/` and use Vitest.
