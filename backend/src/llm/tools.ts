import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import type { FunctionDeclaration } from "@google/genai";

interface ToolSchemaEntry {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
  available_in_phase?: number;
}

interface ToolsJson {
  tools_data: {
    tools: ToolSchemaEntry[];
  };
}

let cachedByPhase: Map<number, FunctionDeclaration[]> = new Map();

function loadToolsJson(): ToolsJson {
  const schemaPath = join(
    dirname(fileURLToPath(import.meta.url)),
    "../../../shared/schema/tools.json",
  );
  return JSON.parse(readFileSync(schemaPath, "utf8")) as ToolsJson;
}

function declarationsForPhase(maxPhase: number): FunctionDeclaration[] {
  const cached = cachedByPhase.get(maxPhase);
  if (cached) return cached;

  const raw = loadToolsJson();
  const declarations = raw.tools_data.tools
    .filter((t) => (t.available_in_phase ?? 99) <= maxPhase)
    .map((t) => ({
      name: t.name,
      description: t.description,
      parameters: t.input_schema,
    }));
  cachedByPhase.set(maxPhase, declarations);
  return declarations;
}

/** Phase 3 tools exposed to the Gemini agent (client-executed). */
export function phase3FunctionDeclarations(): FunctionDeclaration[] {
  return declarationsForPhase(3);
}

/** Phase 4 automation tools (click, type, chords, AppleScript, AX tree). */
export function phase4FunctionDeclarations(): FunctionDeclaration[] {
  return declarationsForPhase(4);
}
