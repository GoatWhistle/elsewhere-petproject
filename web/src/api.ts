import { ElsewhereClient } from "./generated/client";
export type { Future } from "./generated/client";
const client = new ElsewhereClient();
export const createSession = (dream_text: string) => client.createPlanningSession(dream_text);
export const generateFutures = (sessionId: string) => client.generateFutures(sessionId);
