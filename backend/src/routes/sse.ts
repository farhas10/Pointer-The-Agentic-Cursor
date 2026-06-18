import type { Context } from "hono";

import type { SseEvent } from "../types.js";

/**
 * Pumps an AsyncIterable<SseEvent> into an SSE response.
 *
 * Centralized so every route uses the same framing, headers, and
 * abort handling.
 */
export async function streamSse(
  c: Context,
  events: AsyncIterable<SseEvent>,
  controller: AbortController,
): Promise<Response> {
  const encoder = new TextEncoder();

  const stream = new ReadableStream<Uint8Array>({
    async start(controllerStream) {
      try {
        for await (const ev of events) {
          if (controller.signal.aborted) break;
          const frame = formatSseFrame(ev);
          controllerStream.enqueue(encoder.encode(frame));
        }
      } catch (err) {
        const raw = err instanceof Error ? err.message : String(err);
        const errorFrame = formatSseFrame({
          event: "error",
          data: { message: cleanErrorMessage(raw) },
        });
        controllerStream.enqueue(encoder.encode(errorFrame));
      } finally {
        controllerStream.close();
      }
    },
    cancel() {
      controller.abort();
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    },
  });
}

function formatSseFrame(ev: SseEvent): string {
  return `event: ${ev.event}\ndata: ${JSON.stringify(ev.data)}\n\n`;
}

/**
 * Provider SDKs (Anthropic/Gemini) often throw errors whose `.message`
 * is itself a JSON string — sometimes nested several layers deep. This
 * peels those layers and returns the innermost human-readable message
 * so the client shows "API key expired" instead of a wall of escaped JSON.
 */
function cleanErrorMessage(raw: string): string {
  let current = raw.trim();
  for (let depth = 0; depth < 6; depth++) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(current);
    } catch {
      break;
    }
    const next =
      typeof parsed === "object" && parsed !== null
        ? (parsed as { error?: { message?: unknown }; message?: unknown })
        : null;
    const candidate =
      (next?.error && typeof next.error.message === "string"
        ? next.error.message
        : undefined) ??
      (typeof next?.message === "string" ? next.message : undefined);
    if (typeof candidate === "string") {
      current = candidate.trim();
    } else {
      break;
    }
  }
  return current;
}
