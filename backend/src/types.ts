import { z } from "zod";

/* -------------------------------------------------------------------- */
/*  Shared primitives                                                    */
/* -------------------------------------------------------------------- */

export const AppContextSchema = z.object({
  bundle_id: z.string().optional(),
  app_name: z.string().optional(),
  window_title: z.string().optional(),
  url: z.string().optional(),
});
export type AppContext = z.infer<typeof AppContextSchema>;

/** A compact AX snapshot of the element under the cursor at trigger. */
export const AXSnapshotSchema = z.object({
  role: z.string().optional(),
  subrole: z.string().optional(),
  title: z.string().optional(),
  value: z.string().optional(),
  selected_text: z.string().optional(),
  parent_role: z.string().optional(),
  redacted: z.boolean().default(false),
});
export type AXSnapshot = z.infer<typeof AXSnapshotSchema>;

/** Identifier for the chip a user clicked, if any. */
export const ChipIntentSchema = z.enum([
  "explain",
  "translate",
  "summarize",
  "compare",
  "web_search",
  "add_to_drawer",
  "polish",
  "shorten",
  "make_formal",
  "reply",
  "describe",
  "ocr",
  "explain_chart",
  "find_similar",
  "what_does_this_do",
  "click_it_for_me",
  "find_bug",
  "refactor",
  "add_docs",
  "fix_it",
  "fill_with_my_info",
  "explain_field",
  "validate_before_submit",
]);
export type ChipIntent = z.infer<typeof ChipIntentSchema>;

/* -------------------------------------------------------------------- */
/*  POST /v1/agent/ask                                                   */
/* -------------------------------------------------------------------- */

export const LocationSchema = z.object({
  latitude: z.number().optional(),
  longitude: z.number().optional(),
  accuracy_meters: z.number().optional(),
  city: z.string().optional(),
  source: z.enum(["gps", "saved"]),
});
export type LocationContext = z.infer<typeof LocationSchema>;

export const EntityContextEntrySchema = z.object({
  index: z.number().int().positive(),
  name: z.string().max(200),
  subtitle: z.string().max(500).optional(),
  url: z.string().max(2_000).optional(),
  kind: z.enum(["place", "link", "product", "generic"]).optional(),
});
export type EntityContextEntry = z.infer<typeof EntityContextEntrySchema>;

export const AskRequestSchema = z.object({
  prompt: z.string().min(1).max(8_000),
  chip_intent: ChipIntentSchema.optional(),
  ax_snapshot: AXSnapshotSchema.optional(),
  image_b64: z.string().optional(),
  image_mime: z.enum(["image/png", "image/jpeg", "image/webp"]).optional(),
  app_context: AppContextSchema.optional(),
  /** Phase 4: short string summarizing the on-device ambient buffer. */
  ambient_summary: z.string().max(2_000).optional(),
  location: LocationSchema.optional(),
  adapter_hint: z.string().max(4_000).optional(),
  /** Stable id for multi-turn companion sessions in the panel. */
  panel_session_id: z.string().uuid().optional(),
  refresh_context: z.boolean().optional(),
  entity_context: z.array(EntityContextEntrySchema).max(20).optional(),
  /** Pixel width of image_b64 when using Computer Use automation. */
  screen_width: z.number().int().positive().optional(),
  /** Pixel height of image_b64 when using Computer Use automation. */
  screen_height: z.number().int().positive().optional(),
});
export type AskRequest = z.infer<typeof AskRequestSchema>;

/* -------------------------------------------------------------------- */
/*  POST /v1/agent/search                                                */
/* -------------------------------------------------------------------- */

export const WebSearchRequestSchema = z.object({
  query: z.string().min(1).max(500),
});
export type WebSearchRequest = z.infer<typeof WebSearchRequestSchema>;

export const WebSearchResponseSchema = z.object({
  text: z.string(),
  sources: z.array(z.string()),
});
export type WebSearchResponse = z.infer<typeof WebSearchResponseSchema>;

/* -------------------------------------------------------------------- */
/*  POST /v1/agent/places                                                */
/* -------------------------------------------------------------------- */

export const PlacesSearchRequestSchema = z.object({
  query: z.string().min(1).max(500),
  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional(),
  city: z.string().max(200).optional(),
});
export type PlacesSearchRequest = z.infer<typeof PlacesSearchRequestSchema>;

export const PlacesSearchResponseSchema = z.object({
  text: z.string(),
  sources: z.array(z.string()),
});
export type PlacesSearchResponse = z.infer<typeof PlacesSearchResponseSchema>;

/* -------------------------------------------------------------------- */
/*  POST /v1/agent/transcribe                                            */
/* -------------------------------------------------------------------- */

export const TranscribeRequestSchema = z.object({
  audio_b64: z.string().min(1).max(3_000_000),
  audio_mime: z.enum(["audio/mp4", "audio/m4a", "audio/wav", "audio/mpeg"]),
});
export type TranscribeRequest = z.infer<typeof TranscribeRequestSchema>;

export const TranscribeResponseSchema = z.object({
  text: z.string(),
});
export type TranscribeResponse = z.infer<typeof TranscribeResponseSchema>;

/* -------------------------------------------------------------------- */
/*  POST /v1/drawer/query  (Phase 2)                                     */
/* -------------------------------------------------------------------- */

export const DrawerItemSchema = z.discriminatedUnion("kind", [
  z.object({
    kind: z.literal("text"),
    item_id: z.string(),
    label: z.string().optional(),
    chunks: z
      .array(z.object({ chunk_id: z.string(), text: z.string() }))
      .max(64),
  }),
  z.object({
    kind: z.literal("image"),
    item_id: z.string(),
    label: z.string().optional(),
    image_b64: z.string(),
    image_mime: z.enum(["image/png", "image/jpeg", "image/webp"]),
    ocr_text: z.string().optional(),
  }),
  z.object({
    kind: z.literal("url"),
    item_id: z.string(),
    label: z.string().optional(),
    url: z.string(),
    extracted_text_chunks: z
      .array(z.object({ chunk_id: z.string(), text: z.string() }))
      .max(32)
      .optional(),
  }),
]);
export type DrawerItem = z.infer<typeof DrawerItemSchema>;

export const DrawerQueryRequestSchema = z.object({
  drawer_id: z.string(),
  drawer_name: z.string().optional(),
  prompt: z.string().min(1).max(8_000),
  chip_intent: z
    .enum(["compare", "summarize", "find", "extract", "brief"])
    .optional(),
  items: z.array(DrawerItemSchema).min(1).max(32),
});
export type DrawerQueryRequest = z.infer<typeof DrawerQueryRequestSchema>;

/* -------------------------------------------------------------------- */
/*  POST /v1/agent/continue — resume after client tool execution       */
/* -------------------------------------------------------------------- */

export const AgentContinueRequestSchema = z.object({
  session_id: z.string().uuid(),
  tool_results: z
    .array(
      z.object({
        id: z.string(),
        name: z.string(),
        result: z.unknown(),
        screenshot_b64: z.string().optional(),
        screenshot_mime: z
          .enum(["image/png", "image/jpeg", "image/webp"])
          .optional(),
        screen_width: z.number().int().positive().optional(),
        screen_height: z.number().int().positive().optional(),
        url: z.string().optional(),
      }),
    )
    .min(1),
});
export type AgentContinueRequest = z.infer<typeof AgentContinueRequestSchema>;

/* -------------------------------------------------------------------- */
/*  SSE event payloads                                                   */
/* -------------------------------------------------------------------- */

export type SseEvent =
  | { event: "token"; data: { text: string } }
  | {
      event: "tool_call";
      data: {
        name: string;
        input: unknown;
        id: string;
        session_id: string;
        tier: "safe" | "automation" | "destructive";
      };
    }
  | { event: "citation"; data: { item_id: string; chunk_id?: string } }
  | { event: "error"; data: { message: string; code?: string } }
  | {
      event: "done";
      data: {
        finish_reason: "stop" | "tool_use" | "length" | "content_filter";
        usage?: { input_tokens: number; output_tokens: number };
        session_id?: string;
        agent_mode?: "qa" | "automation";
      };
    };
