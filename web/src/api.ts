import { DreamInput, ElsewhereClient } from "./generated/client";

export type { DreamInput, Future, PlanningSession } from "./generated/client";

const client = new ElsewhereClient(import.meta.env.VITE_API_BASE_URL || "http://localhost:3000");

export const createSession = (input: DreamInput, signal?: AbortSignal) =>
  client.createPlanningSession(input, signal);
export const generateFutures = (sessionId: string) => client.generateFutures(sessionId);
