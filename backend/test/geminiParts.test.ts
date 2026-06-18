import type { GenerateContentResponse } from "@google/genai";
import { describe, expect, it } from "vitest";

import {
  visibleTextFromParts,
  visibleTextFromResponse,
} from "../src/llm/geminiParts.js";

describe("visibleTextFromParts", () => {
  it("joins non-thought text parts", () => {
    expect(
      visibleTextFromParts([
        { text: "Hello " },
        { text: "world" },
      ]),
    ).toBe("Hello world");
  });

  it("skips thought parts and function calls", () => {
    expect(
      visibleTextFromParts([
        { text: "hidden", thought: true },
        { functionCall: { name: "read_ax_tree", args: {}, id: "1" } },
        { text: "visible" },
      ]),
    ).toBe("visible");
  });
});

describe("visibleTextFromResponse", () => {
  it("reads text from candidate parts", () => {
    expect(
      visibleTextFromResponse({
        candidates: [{ content: { parts: [{ text: "Answer" }] } }],
      } as unknown as GenerateContentResponse),
    ).toBe("Answer");
  });
});
