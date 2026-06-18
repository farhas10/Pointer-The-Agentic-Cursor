import { randomUUID } from "node:crypto";

import type { Content } from "@google/genai";

import type { AgentMode } from "./agentMode.js";
import type { ChipIntent } from "../types.js";

export interface AgentSession {
  id: string;
  contents: Content[];
  createdAt: number;
  pendingToolIds: string[];
  /** Bundle id of the foreground app when the session started. */
  foregroundBundleId?: string;
  /** Panel-level companion id for multi-turn follow-ups. */
  panelSessionId?: string;
  /** qa = fast chat model; automation = Computer Use preview model. */
  mode: AgentMode;
  /** Chip from the latest ask — used to skip tools on fast Q&A paths. */
  chipIntent?: ChipIntent;
  screenWidth?: number;
  screenHeight?: number;
}

const TTL_MS = 15 * 60 * 1000;
const sessions = new Map<string, AgentSession>();
const panelIndex = new Map<string, string>();

export function createSession(
  contents: Content[],
  foregroundBundleId?: string,
  panelSessionId?: string,
  mode: AgentMode = "qa",
  screenWidth?: number,
  screenHeight?: number,
  chipIntent?: ChipIntent,
): AgentSession {
  if (panelSessionId) {
    const existingId = panelIndex.get(panelSessionId);
    if (existingId) {
      const existing = sessions.get(existingId);
      if (existing && Date.now() - existing.createdAt <= TTL_MS) {
        deleteSession(existing.id);
      } else {
        panelIndex.delete(panelSessionId);
      }
    }
  }

  const session: AgentSession = {
    id: randomUUID(),
    contents,
    createdAt: Date.now(),
    pendingToolIds: [],
    foregroundBundleId,
    panelSessionId,
    mode,
    chipIntent,
    screenWidth,
    screenHeight,
  };
  sessions.set(session.id, session);
  if (panelSessionId) {
    panelIndex.set(panelSessionId, session.id);
  }
  pruneExpired();
  return session;
}

export function getSession(id: string): AgentSession | undefined {
  const session = sessions.get(id);
  if (!session) return undefined;
  if (Date.now() - session.createdAt > TTL_MS) {
    deleteSession(id);
    return undefined;
  }
  return session;
}

export function getSessionByPanelId(
  panelSessionId: string,
): AgentSession | undefined {
  const id = panelIndex.get(panelSessionId);
  if (!id) return undefined;
  return getSession(id);
}

export function appendUserTurn(session: AgentSession, contents: Content[]): void {
  session.contents.push(...contents);
  session.createdAt = Date.now();
}

export function deleteSession(id: string): void {
  const session = sessions.get(id);
  if (session?.panelSessionId) {
    panelIndex.delete(session.panelSessionId);
  }
  sessions.delete(id);
}

function pruneExpired(): void {
  const now = Date.now();
  for (const [id, session] of sessions) {
    if (now - session.createdAt > TTL_MS) {
      deleteSession(id);
    }
  }
}
