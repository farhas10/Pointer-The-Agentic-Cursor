import { describe, expect, it, beforeEach } from "vitest";

import { resetProviderForTests } from "../src/llm/registry.js";
import { resetRateLimitForTests } from "../src/middleware/rateLimit.js";
import { createApp } from "../src/server.js";

beforeEach(() => {
  resetProviderForTests();
  resetRateLimitForTests();
  delete process.env.ANTHROPIC_API_KEY;
  delete process.env.DEV_SHARED_SECRET;
});

describe("server", () => {
  it("reports healthz", async () => {
    const app = createApp();
    const res = await app.request("/healthz");
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body).toMatchObject({ ok: true, provider: "mock" });
  });

  it("rejects unknown routes", async () => {
    const app = createApp();
    const res = await app.request("/v1/nope");
    expect(res.status).toBe(404);
  });

  it("rejects malformed ask requests", async () => {
    const app = createApp();
    const res = await app.request("/v1/agent/ask", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ prompt: "" }),
    });
    expect(res.status).toBe(400);
  });

  it("streams SSE events from the mock provider", async () => {
    const app = createApp();
    const res = await app.request("/v1/agent/ask", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        prompt: "What is this?",
        chip_intent: "explain",
      }),
    });
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/event-stream");

    const text = await res.text();
    expect(text).toContain("event: token");
    expect(text).toContain("event: done");
    // Reassemble token text and confirm the canned response is in there.
    const reassembled = Array.from(
      text.matchAll(/event: token\ndata: (\{.*?\})/g),
    )
      .map((m) => JSON.parse(m[1]!).text as string)
      .join("");
    expect(reassembled).toContain("Mock response");
    expect(reassembled).toContain("explain");
  });
});
