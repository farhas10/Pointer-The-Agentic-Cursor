import { z } from "zod";

const EnvSchema = z.object({
  PORT: z.coerce.number().int().positive().default(8787),
  NODE_ENV: z
    .enum(["development", "production", "test"])
    .default("development"),
  LOG_LEVEL: z.enum(["debug", "info", "warn", "error"]).default("info"),

  /** Force a specific provider. If unset, the registry auto-detects
   *  based on which API key is present (Anthropic preferred, then Gemini,
   *  then the mock). */
  LLM_PROVIDER: z.enum(["anthropic", "gemini", "mock"]).optional(),

  ANTHROPIC_API_KEY: z.string().optional(),
  ANTHROPIC_MODEL: z.string().default("claude-sonnet-4-5-20250929"),

  GEMINI_API_KEY: z.string().optional(),
  GEMINI_MODEL: z.string().default("gemini-3.5-flash"),
  /** Computer Use + vision automation (preview models only). */
  GEMINI_AUTOMATION_MODEL: z.string().default("gemini-3-flash-preview"),

  DEV_SHARED_SECRET: z.string().optional(),

  RATE_LIMIT_WINDOW_MS: z.coerce.number().int().positive().default(60_000),
  RATE_LIMIT_MAX: z.coerce.number().int().positive().default(60),
});

export type Config = z.infer<typeof EnvSchema>;

let cached: Config | null = null;

/** Loads & validates env once. Throws on misconfiguration. */
export function getConfig(): Config {
  if (cached) return cached;
  const parsed = EnvSchema.safeParse(process.env);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((i) => `  ${i.path.join(".")}: ${i.message}`)
      .join("\n");
    throw new Error(`Invalid environment configuration:\n${issues}`);
  }
  cached = parsed.data;
  return cached;
}
