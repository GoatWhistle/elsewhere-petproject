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

const base = "http://localhost:3000";
async function json<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${base}${path}`, { headers: { "Content-Type": "application/json" }, ...init });
  if (!response.ok) throw new Error((await response.json()).detail || "Request failed");
  return response.json() as Promise<T>;
}

export async function createSession(dream_text: string) {
  return json<{ id: string; travel_dna: { elements: Array<{ dimension: string; provenance: string }> } }>("/planning-sessions", { method: "POST", body: JSON.stringify({ dream_text, origin: "MOW", date_window: { from: "2026-07-08", to: "2026-07-15" }, party: { adults: 2, children: 0 } }) });
}
export async function generateFutures(sessionId: string) {
  await json(`/planning-sessions/${sessionId}/futures`, { method: "POST", body: "{}" });
  return json<{ futures: Future[] }>(`/planning-sessions/${sessionId}/futures`);
}

