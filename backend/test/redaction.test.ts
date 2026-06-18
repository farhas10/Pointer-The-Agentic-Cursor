import { describe, expect, it } from "vitest";

import { redactAskRequest } from "../src/safety/redaction.js";
import type { AskRequest } from "../src/types.js";

const base: AskRequest = {
  prompt: "What is this?",
};

describe("redactAskRequest", () => {
  it("passes through requests with no AX snapshot", () => {
    expect(redactAskRequest(base)).toBe(base);
  });

  it("passes through non-secure AX snapshots", () => {
    const req: AskRequest = {
      ...base,
      ax_snapshot: {
        role: "AXStaticText",
        value: "hello world",
        redacted: false,
      },
    };
    expect(redactAskRequest(req)).toEqual(req);
  });

  it("redacts AXSecureTextField content", () => {
    const req: AskRequest = {
      ...base,
      ax_snapshot: {
        role: "AXSecureTextField",
        value: "hunter2",
        selected_text: "hunter2",
        redacted: false,
      },
    };
    const out = redactAskRequest(req);
    expect(out.ax_snapshot?.value).toBeUndefined();
    expect(out.ax_snapshot?.selected_text).toBeUndefined();
    expect(out.ax_snapshot?.redacted).toBe(true);
  });

  it("redacts when title hints at password", () => {
    const req: AskRequest = {
      ...base,
      ax_snapshot: {
        role: "AXTextField",
        title: "Password",
        value: "letmein",
        redacted: false,
      },
    };
    const out = redactAskRequest(req);
    expect(out.ax_snapshot?.value).toBeUndefined();
    expect(out.ax_snapshot?.redacted).toBe(true);
  });

  it("does not mutate the input", () => {
    const req: AskRequest = {
      ...base,
      ax_snapshot: {
        role: "AXSecureTextField",
        value: "secret",
        redacted: false,
      },
    };
    const snapshot = JSON.stringify(req);
    redactAskRequest(req);
    expect(JSON.stringify(req)).toBe(snapshot);
  });
});
