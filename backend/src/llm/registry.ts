import { getConfig } from "../config.js";
import { AnthropicProvider } from "./anthropic.js";
import { GeminiProvider } from "./gemini.js";
import { MockProvider } from "./mock.js";
import type { LLMProvider } from "./provider.js";

let cached: LLMProvider | null = null;

/**
 * Returns the active LLM provider, picked at first call based on env.
 *
 * - If `LLM_PROVIDER` is set, that provider is used (and must have its key).
 * - Otherwise auto-detect: Anthropic key → Anthropic, else Gemini key →
 *   Gemini, else MockProvider (so the client can develop without keys).
 */
export function getProvider(): LLMProvider {
  if (cached) return cached;
  const config = getConfig();

  switch (config.LLM_PROVIDER) {
    case "anthropic":
      cached = config.ANTHROPIC_API_KEY
        ? new AnthropicProvider(config)
        : warnAndMock("anthropic");
      return cached;
    case "gemini":
      cached = config.GEMINI_API_KEY
        ? new GeminiProvider(config)
        : warnAndMock("gemini");
      return cached;
    case "mock":
      cached = new MockProvider();
      return cached;
    default:
      break;
  }

  if (config.ANTHROPIC_API_KEY) {
    cached = new AnthropicProvider(config);
  } else if (config.GEMINI_API_KEY) {
    cached = new GeminiProvider(config);
  } else {
    cached = new MockProvider();
  }
  return cached;
}

/** Test-only: reset the cached provider. */
export function resetProviderForTests(): void {
  cached = null;
}

function warnAndMock(forced: string): LLMProvider {
  // eslint-disable-next-line no-console
  console.warn(
    `LLM_PROVIDER=${forced} but its API key is missing — falling back to the mock provider. Set the key in backend/.env.`,
  );
  return new MockProvider();
}
