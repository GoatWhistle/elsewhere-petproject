// Contract-shaped MSW handlers. They mirror the frozen OpenAPI resources and
// can be enabled by the demo entrypoint without a running Rails process.
import { http, HttpResponse } from "msw";

export const handlers = [
  http.post("*/planning-sessions", async () => HttpResponse.json({ id: "fixture-session", travel_dna: { elements: [] } }, { status: 201 })),
  http.get("*/planning-sessions/:sessionId/futures", async () => HttpResponse.json({ futures: [], diversity_note: "fixture" })),
];

