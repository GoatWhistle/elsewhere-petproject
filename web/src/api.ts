import { DreamInput, ElsewhereClient, SimulationRequest, TravelDnaElementInput } from "./generated/client";

export type {
  DreamInput,
  Forecast,
  Future,
  Job,
  PlanningSession,
  SimulationRequest,
  TravelDnaElementInput,
} from "./generated/client";

const client = new ElsewhereClient(import.meta.env.VITE_API_BASE_URL || "http://localhost:3000");

export const createSession = (input: DreamInput, signal?: AbortSignal) =>
  client.createPlanningSession(input, signal);
export const updateTravelDna = (sessionId: string, elements: TravelDnaElementInput[]) =>
  client.updateTravelDna(sessionId, elements);
export const generateFutures = (sessionId: string) => client.generateFutures(sessionId);

// The contract answers 202 with a job reference; polling belongs here rather than in a component, so a panel
// only ever sees a settled Job.
export const simulateFuture = async (futureId: string, request: SimulationRequest) => {
  const accepted = await client.simulateFuture(futureId, request);
  return accepted.status === "succeeded" || accepted.status === "failed"
    ? accepted
    : client.awaitJob(accepted.id);
};

export const applyMitigation = async (futureId: string, riskId: string, mitigationId: string) => {
  const accepted = await client.applyMitigation(futureId, riskId, mitigationId);
  return accepted.status === "succeeded" || accepted.status === "failed"
    ? accepted
    : client.awaitJob(accepted.id);
};

export const getForecast = (futureId: string) => client.getForecast(futureId);
