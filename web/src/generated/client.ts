// Generated boundary for docs/04_api/openapi.yaml. The Phase 0 client keeps the
// same operation names and resource types while avoiding a generator runtime.
export type Money = { amount_minor: number; currency: string };
export type Future = {
  id: string;
  destination: { name: string; country: string };
  accommodation: { name: string; distance_to_sea_m: number | null };
  price: { total: Money; components: Array<{ kind: string; amount: Money; fulfilment: "estimate" | "modeled" }> };
  match: { score: number; confidence: number; contributions: Array<{ dimension: string; contribution: number }> };
  why_this_exists: string;
  compromises: string[];
};

export class ElsewhereClient {
  constructor(private readonly baseUrl = "http://localhost:3000") {}
  async createPlanningSession(dream_text: string) {
    return this.request<{ id: string; travel_dna: { elements: Array<{ dimension: string; provenance: string }> } }>("/planning-sessions", { method: "POST", body: JSON.stringify({ dream_text, origin: "MOW", date_window: { earliest: "2026-07-01", latest: "2026-07-31", nights_min: 6, nights_max: 7 }, party: { adults: 2 } }) });
  }
  async generateFutures(sessionId: string) {
    await this.request(`/planning-sessions/${sessionId}/futures`, { method: "POST", body: "{}" });
    return this.request<{ futures: Future[] }>(`/planning-sessions/${sessionId}/futures`);
  }
  private async request<T>(path: string, init?: RequestInit): Promise<T> {
    const response = await fetch(`${this.baseUrl}${path}`, { headers: { "Content-Type": "application/json" }, ...init });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.detail || "Request failed");
    return payload as T;
  }
}
