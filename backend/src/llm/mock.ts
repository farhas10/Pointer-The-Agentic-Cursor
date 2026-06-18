import type { AskRequest, DrawerQueryRequest, SseEvent } from "../types.js";
import type { LLMProvider } from "./provider.js";

/**
 * Deterministic mock provider used when no `ANTHROPIC_API_KEY` is set.
 *
 * Streams a canned response one word at a time with a small delay so
 * the client's SSE handling can be exercised without burning credits
 * or needing network. Includes the chip intent and a short echo of
 * the prompt so it's obvious the wiring works end-to-end.
 */
export class MockProvider implements LLMProvider {
  readonly name = "mock";

  async *ask(
    req: AskRequest,
    signal: AbortSignal,
  ): AsyncIterable<SseEvent> {
    const intent = req.chip_intent ?? "ask";
    const elementHint =
      req.ax_snapshot?.title ??
      req.ax_snapshot?.value?.slice(0, 60) ??
      "the element under your cursor";

    const message =
      `**Mock response (no Anthropic key configured).** ` +
      `Intent: \`${intent}\`. ` +
      `You asked about ${elementHint}. ` +
      `Your prompt was: "${req.prompt.slice(0, 200)}". ` +
      `Set ANTHROPIC_API_KEY in backend/.env to get real answers.`;

    yield* streamWords(message, signal);
    yield {
      event: "done",
      data: {
        finish_reason: "stop",
        usage: { input_tokens: 0, output_tokens: message.split(/\s+/).length },
      },
    };
  }

  async *queryDrawer(
    req: DrawerQueryRequest,
    signal: AbortSignal,
  ): AsyncIterable<SseEvent> {
    const itemList = req.items
      .map((i) => `${i.kind}:${i.item_id}`)
      .slice(0, 5)
      .join(", ");

    const message =
      `**Mock drawer response.** Drawer: \`${req.drawer_name ?? req.drawer_id}\`. ` +
      `Received ${req.items.length} items (${itemList}${req.items.length > 5 ? ", …" : ""}). ` +
      `Real answers require ANTHROPIC_API_KEY. ` +
      `Citation [${req.items[0]!.item_id}].`;

    yield* streamWords(message, signal);

    if (req.items[0]) {
      yield {
        event: "citation",
        data: { item_id: req.items[0].item_id },
      };
    }

    yield {
      event: "done",
      data: {
        finish_reason: "stop",
        usage: { input_tokens: 0, output_tokens: message.split(/\s+/).length },
      },
    };
  }
}

async function* streamWords(
  text: string,
  signal: AbortSignal,
): AsyncIterable<SseEvent> {
  const words = text.split(/(\s+)/); // keep whitespace
  for (const w of words) {
    if (signal.aborted) return;
    yield { event: "token", data: { text: w } };
    await sleep(15, signal);
  }
}

function sleep(ms: number, signal: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal.aborted) {
      reject(new Error("aborted"));
      return;
    }
    const t = setTimeout(() => {
      signal.removeEventListener("abort", onAbort);
      resolve();
    }, ms);
    const onAbort = () => {
      clearTimeout(t);
      reject(new Error("aborted"));
    };
    signal.addEventListener("abort", onAbort, { once: true });
  });
}
