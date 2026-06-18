import type { AskRequest } from "../types.js";

/**
 * Server-side defense in depth. The mac client is supposed to redact
 * AXSecureTextField content before sending, but we strip a few obvious
 * shapes here as well.
 *
 * Returns a *new* request; never mutates the input.
 */
export function redactAskRequest(req: AskRequest): AskRequest {
  if (!req.ax_snapshot) return req;

  const role = req.ax_snapshot.role ?? "";
  const isSecure =
    role === "AXSecureTextField" ||
    role === "AXPasswordField" ||
    /password|secure/i.test(req.ax_snapshot.title ?? "");

  if (!isSecure) return req;

  return {
    ...req,
    ax_snapshot: {
      ...req.ax_snapshot,
      value: undefined,
      selected_text: undefined,
      redacted: true,
    },
  };
}
