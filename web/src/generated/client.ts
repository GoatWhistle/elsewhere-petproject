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

export type TravelDnaElementInput = {
  dimension: Dimension;
  kind: TravelDnaElement["kind"];
  target?: unknown;
  weight?: number | null;
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

export type TravelLeg = {
  origin: string;
  destination: string;
  depart_at: string;
  arrive_at: string;
  carrier?: string | null;
  stops: number;
  duration_min: number;
  as_of: string;
  booking_url?: string | null;
};

export type Logistics = {
  outbound: TravelLeg;
  inbound: TravelLeg;
  airport_transfer: {
    mode: "private" | "shared" | "public" | "walk";
    duration_min: number;
    note?: string;
  };
  local_mobility: {
    assumption: string;
    walkable?: boolean;
  };
};

export type PriceComponent = {
  kind: "travel" | "accommodation" | "transfer" | "local_mobility";
  amount: Money;
  fulfilment: "estimate" | "modeled";
  source?: string;
  handoff_url?: string | null;
  as_of?: string | null;
};

export type MatchContribution = {
  dimension: Dimension;
  satisfaction: number;
  weight: number;
  contribution: number;
  confidence: number;
  explanation?: string;
};

export type UnscoredDimension = {
  dimension: Dimension;
  reason: string;
};

export type Future = {
  id: string;
  lineage_id: string;
  travel_dna_version_id: string;
  version: number;
  parent_id?: string | null;
  created_at: string;
  expires_at: string;
  destination: {
    city_code: string;
    name: string;
    country: string;
    coordinates?: { lat: number; lon: number };
  };
  check_in: string;
  check_out: string;
  accommodation: {
    catalogue_id: string;
    name: string;
    room_name: string;
    handoff_url?: string | null;
    coordinates?: { lat: number; lon: number };
    cancellation?: {
      refundable: boolean;
      free_until?: string | null;
      summary: string;
    };
    distance_to_sea_m: number | null;
    distance_to_centre_m?: number | null;
  };
  logistics: Logistics;
  price: {
    total: Money;
    components: PriceComponent[];
  };
  match: {
    score: number;
    coverage: number;
    confidence: number;
    contributions: MatchContribution[];
    unscored_dimensions: UnscoredDimension[];
  };
  why_this_exists: string;
  benefits: string[];
  compromises: string[];
  delta?: Delta | null;
  forecast_summary?: RiskSummary[];
};

export type RiskType =
  | "night_noise"
  | "crowds"
  | "walkability"
  | "weather_mismatch"
  | "construction"
  | "transfer_difficulty"
  | "weak_transport"
  | "room_location_mismatch"
  | "seasonal_closure";

export type Severity = "low" | "medium" | "high";

export type Evidence = {
  source: "review" | "geo" | "weather" | "seasonality" | "provider_metadata";
  excerpt?: string;
  observed_at?: string | null;
  count?: number | null;
};

export type Mitigation = {
  id: string;
  description: string;
  price_change: Money;
  severity_after: Severity;
};

export type RiskSummary = {
  id: string;
  risk_type: RiskType;
  severity: Severity;
};

export type RiskItem = {
  id: string;
  risk_type: RiskType;
  severity: Severity;
  confidence: number;
  claim_kind: "verified_fact" | "derived_metric" | "model_inference";
  affected_dimension: Dimension;
  statement: string;
  evidence: Evidence[];
  mitigations?: Mitigation[];
};

export type Coverage = {
  risk_type: RiskType;
  assessed: boolean;
  reason?: string;
};

export type Forecast = {
  future_id: string;
  generated_at: string;
  risks: RiskItem[];
  coverage: Coverage[];
};

export type Adjustment = {
  dimension: Dimension;
  direction: "increase" | "decrease";
  magnitude?: number;
};

export type SimulationRequest =
  | { adjustments: Adjustment[]; persist_to_travel_dna?: boolean }
  | { instruction: string; persist_to_travel_dna?: boolean };

export type DeltaItem = {
  description: string;
  amount: Money;
  relaxed_dimension?: Dimension | null;
};

export type Delta = {
  from_future_id: string;
  price_before: Money;
  price_after: Money;
  price_change: Money;
  items: DeltaItem[];
  match_before: number;
  match_after: number;
  dimension_changes: { dimension: Dimension; change: "improved" | "worsened" | "unchanged" }[];
  new_risks: RiskSummary[];
  resolved_risks: RiskSummary[];
  explanation?: string;
};

export type NoSolution = {
  reason: string;
  unsatisfiable_constraints: Dimension[];
  nearest_alternatives: Future[];
};

export type JobResult = {
  kind: "futures" | "future" | "no_solution";
  futures?: Future[];
  future?: Future;
  no_solution?: NoSolution;
};

export type Job = {
  id: string;
  status: "queued" | "running" | "succeeded" | "failed";
  kind: "generate_futures" | "simulate" | "apply_mitigation";
  created_at: string;
  result?: JobResult | null;
  error?: ProblemDetails | null;
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

  updateTravelDna(sessionId: string, elements: TravelDnaElementInput[]) {
    return this.request<TravelDna>(`/planning-sessions/${sessionId}/travel-dna`, {
      method: "PATCH",
      body: JSON.stringify({ elements }),
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

  getFuture(futureId: string) {
    return this.request<Future>(`/futures/${futureId}`);
  }

  // Simulation is a job: the contract answers 202 with a Job reference and the client polls.
  simulateFuture(futureId: string, body: SimulationRequest) {
    return this.request<Job>(`/futures/${futureId}/simulations`, {
      method: "POST",
      body: JSON.stringify(body),
    });
  }

  applyMitigation(futureId: string, riskId: string, mitigationId: string) {
    return this.request<Job>(
      `/futures/${futureId}/forecast/risks/${riskId}/mitigations/${mitigationId}`,
      { method: "POST", body: "{}" },
    );
  }

  getJob(jobId: string) {
    return this.request<Job>(`/jobs/${jobId}`);
  }

  getForecast(futureId: string) {
    return this.request<Forecast>(`/futures/${futureId}/forecast`);
  }

  // Poll until the job settles. A simulation that never finishes is a bug worth surfacing, not a spinner
  // that spins forever, so the wait is bounded and the timeout is an error the caller can show.
  async awaitJob(jobId: string, { intervalMs = 400, timeoutMs = 20_000 } = {}): Promise<Job> {
    const startedAt = Date.now();

    for (;;) {
      const job = await this.getJob(jobId);
      if (job.status === "succeeded" || job.status === "failed") return job;
      if (Date.now() - startedAt > timeoutMs) {
        throw new ApiProblem(504, { title: "Расчёт занял слишком долго", status: 504 });
      }
      await new Promise((resolve) => setTimeout(resolve, intervalMs));
    }
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
