import { describe, expect, it } from "vitest";

import {
  isQaFastChip,
  QA_FAST_CHIPS,
  resolveAgentMode,
} from "../src/agent/agentMode.js";

describe("resolveAgentMode", () => {
  it("uses automation for action chips", () => {
    expect(
      resolveAgentMode({ prompt: "go", chip_intent: "click_it_for_me" }),
    ).toBe("automation");
  });

  it("uses qa for explain chips", () => {
    expect(resolveAgentMode({ prompt: "what is this?", chip_intent: "explain" })).toBe(
      "qa",
    );
  });

  it("uses qa for imperative prompts (AX tools, not Computer Use)", () => {
    expect(resolveAgentMode({ prompt: "click the submit button" })).toBe("qa");
    expect(resolveAgentMode({ prompt: "open Safari" })).toBe("qa");
  });

  it("uses qa for research prompts", () => {
    expect(resolveAgentMode({ prompt: "what do reviews say about this place?" })).toBe(
      "qa",
    );
  });

  it("uses qa for web search chip", () => {
    expect(resolveAgentMode({ prompt: "coffee shops", chip_intent: "web_search" })).toBe(
      "qa",
    );
  });
});

describe("isQaFastChip", () => {
  it("recognizes fast-path chips", () => {
    expect(isQaFastChip("explain")).toBe(true);
    expect(isQaFastChip("web_search")).toBe(false);
    expect(isQaFastChip(undefined)).toBe(false);
  });

  it("covers all QA_FAST_CHIPS", () => {
    for (const chip of QA_FAST_CHIPS) {
      expect(isQaFastChip(chip)).toBe(true);
    }
  });
});
