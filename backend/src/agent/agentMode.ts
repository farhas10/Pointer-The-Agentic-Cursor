import type { AskRequest, ChipIntent } from "../types.js";

export type AgentMode = "qa" | "automation";

const AUTOMATION_CHIPS = new Set<ChipIntent>([
  "click_it_for_me",
  "fill_with_my_info",
  "validate_before_submit",
]);

/** Q&A chips that use the fast model without Computer Use. */
export const QA_FAST_CHIPS = new Set<ChipIntent>([
  "explain",
  "translate",
  "summarize",
  "compare",
  "polish",
  "shorten",
  "make_formal",
  "reply",
  "describe",
  "ocr",
  "explain_chart",
  "find_similar",
  "what_does_this_do",
  "explain_field",
  "find_bug",
  "refactor",
  "add_docs",
  "fix_it",
]);

/** Route Q&A to gemini-3.5-flash; Computer Use only for action chips. */
export function resolveAgentMode(req: AskRequest): AgentMode {
  if (req.chip_intent && AUTOMATION_CHIPS.has(req.chip_intent)) {
    return "automation";
  }
  return "qa";
}

export function isQaFastChip(chip: ChipIntent | undefined): boolean {
  return chip != null && QA_FAST_CHIPS.has(chip);
}
