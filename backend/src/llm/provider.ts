import type { AskRequest, DrawerQueryRequest, SseEvent } from "../types.js";

/**
 * Abstract LLM provider interface.
 *
 * Implementations: AnthropicProvider, MockProvider, (later) OpenAIProvider.
 *
 * Both methods return an AsyncIterable of SseEvent so routes can simply
 * pipe events to the SSE response.
 */
export interface LLMProvider {
  readonly name: string;

  ask(req: AskRequest, signal: AbortSignal): AsyncIterable<SseEvent>;

  queryDrawer(
    req: DrawerQueryRequest,
    signal: AbortSignal,
  ): AsyncIterable<SseEvent>;
}
