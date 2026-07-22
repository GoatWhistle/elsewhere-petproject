// Generated boundary for docs/04_api/openapi.yaml. Until code generation is
// wired into bin/check, this file mirrors the frozen contract explicitly.

export type Money = {
  amount_minor: number;
  currency: string;
};

export type DateWindow = {
  earliest: string;
  latest: string;
  nights_min: number;
  nights_max: number;
};

export type Party = {
  adults: 1 | 2;
};

export type DreamInput = {
  dream_text: string;
  origin: string;
  date_window: DateWindow;
  party: Party;
  budget_total?: Money | null;
};

export type Dimension =
  | "total_budget"
  | "trip_length"
  | "dates"
  | "sea_access"
  | "climate_warm"
  | "quiet"
  | "food_quality"
  | "walkability"
  | "nature_vs_city"
  | "crowds"
  | "nightlife"
  | "comfort"
  | "car_free"
  | "transfer_simplicity";

export type TravelDnaElement = {
  dimension: Dimension;
  kind: "hard_constraint" | "preference" | "aversion";
  target?: unknown;
  weight?: number | null;
  tolerance?: number | null;
  provenance: "stated" | "inferred" | "confirmed" | "default";
  confidence: number;
};

export type TravelDna = {
  id: string;
  version: number;
  elements: TravelDnaElement[];
  unmatched_intent: string[];
};

export type Clarification = {
  id: string;
  dimension?: Dimension;
  question: string;
  why_it_matters: string;
  options?: Array<{ value: unknown; label: string }>;
};

export type PlanningSession = {
  id: string;
  created_at: string;
  dream_text: string;
  travel_dna: TravelDna;
  clarifications: Clarification[];
};

export type Future = {
  id: string;
  destination: { name: string; country: string };
  accommodation: { name: string; distance_to_sea_m: number | null };
  price: {
    total: Money;
    components: Array<{
      kind: string;
      amount: Money;
      fulfilment: "estimate" | "modeled";
    }>;
  };
  match: {
    score: number;
    confidence: number;
    contributions: Array<{ dimension: string; contribution: number }>;
  };
  why_this_exists: string;
  compromises: string[];
};

export type ProblemDetails = {
  type?: string;
  title?: string;
  status?: number;
  detail?: string;
  instance?: string;
};

export class ApiProblem extends Error {
  constructor(
    public readonly status: number,
    public readonly problem: ProblemDetails,
  ) {
    super(problem.detail || problem.title || "Не удалось выполнить запрос");
    this.name = "ApiProblem";
  }
}

export class ElsewhereClient {
  constructor(private readonly baseUrl = "http://localhost:3000") {}

  createPlanningSession(input: DreamInput, signal?: AbortSignal) {
    return this.request<PlanningSession>("/planning-sessions", {
      method: "POST",
      body: JSON.stringify(input),
      signal,
    });
  }

  async generateFutures(sessionId: string) {
    await this.request(`/planning-sessions/${sessionId}/futures`, {
      method: "POST",
      body: "{}",
    });
    return this.request<{ futures: Future[]; diversity_note?: string | null }>(
      `/planning-sessions/${sessionId}/futures`,
    );
  }

  private async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const headers = new Headers(init.headers);
    if (!headers.has("Content-Type")) headers.set("Content-Type", "application/json");

    const response = await fetch(`${this.baseUrl}${path}`, {
      ...init,
      headers,
    });
    const body = await response.text();
    let payload: unknown = null;

    if (body) {
      try {
        payload = JSON.parse(body);
      } catch {
        if (response.ok) throw new Error("Сервис вернул ответ в неизвестном формате");
      }
    }

    if (!response.ok) {
      const problem = isProblemDetails(payload)
        ? payload
        : { title: "Не удалось выполнить запрос", status: response.status };
      throw new ApiProblem(response.status, problem);
    }

    return payload as T;
  }
}

function isProblemDetails(value: unknown): value is ProblemDetails {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
