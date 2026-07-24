// Contract-shaped development responses for the frozen OpenAPI resources.
import { http, HttpResponse } from "msw";
import type {
  Delta,
  DreamInput,
  Forecast,
  Future,
  Job,
  Money,
  PlanningSession,
  ProblemDetails,
  TravelDnaElement,
  TravelDnaElementInput,
} from "../generated/client";

const SESSION_ID = "03571d18-8537-48aa-995c-fc0f9a41ba51";
const sessions = new Map<string, { session: PlanningSession; input: DreamInput }>();
const futures = new Map<string, Future>();
const jobs = new Map<string, Job>();
let nextSessionNumber = 1;
let nextJobNumber = 1;

export const handlers = [
  http.post("*/planning-sessions", async ({ request }) => {
    const payload: unknown = await request.json().catch(() => null);

    if (!isDreamInput(payload)) {
      return problemResponse({
        type: "https://elsewhere.example/problems/invalid-dream",
        title: "Некорректные данные поездки",
        status: 422,
        detail: "Заполните описание, город вылета, окно дат, длительность и число взрослых.",
      });
    }

    const sessionId = createSessionId(nextSessionNumber++);
    const session: PlanningSession = {
      id: sessionId,
      created_at: "2026-08-28T09:00:00Z",
      dream_text: payload.dream_text,
      travel_dna: {
        id: travelDnaVersionId(sessionId, 1),
        version: 1,
        elements: [
          {
            dimension: "dates",
            kind: "hard_constraint",
            target: payload.date_window,
            weight: null,
            tolerance: null,
            provenance: "stated",
            confidence: 1,
          },
          {
            dimension: "trip_length",
            kind: "hard_constraint",
            target: {
              min: payload.date_window.nights_min,
              max: payload.date_window.nights_max,
            },
            weight: null,
            tolerance: null,
            provenance: "stated",
            confidence: 1,
          },
          {
            dimension: "quiet",
            kind: "preference",
            target: 0.8,
            weight: 0.7,
            tolerance: 0.2,
            provenance: "inferred",
            confidence: 0.6,
          },
        ],
        unmatched_intent: [],
      },
      clarifications: [
        {
          id: "budget-ceiling",
          dimension: "total_budget",
          question: "Указанный бюджет — жёсткий потолок?",
          why_it_matters: "От ответа зависит, исключать ли более дорогие варианты полностью.",
          options: [
            { value: true, label: "Да, не превышать" },
            { value: false, label: "Можно немного выше" },
          ],
        },
      ],
    };

    sessions.set(session.id, { session, input: payload });
    return HttpResponse.json(session, { status: 201 });
  }),

  http.patch("*/planning-sessions/:sessionId/travel-dna", async ({ params, request }) => {
    const payload = await request.json().catch(() => null) as { elements?: unknown } | null;
    const sessionId = String(params.sessionId);
    const stored = sessions.get(sessionId);
    if (!stored) {
      return problemResponse({ title: "Сессия не найдена", status: 404 });
    }
    if (!Array.isArray(payload?.elements)) {
      return problemResponse({ title: "Некорректная Travel DNA", status: 422, detail: "Нужен список элементов." });
    }

    const elements = payload.elements as TravelDnaElementInput[];
    const version = stored.session.travel_dna.version + 1;
    const session = {
      ...stored.session,
      travel_dna: {
        ...stored.session.travel_dna,
        id: travelDnaVersionId(sessionId, version),
        version,
        elements: upsertTravelDnaElements(stored.session.travel_dna.elements, elements),
      },
    };
    sessions.set(sessionId, { ...stored, session });
    return HttpResponse.json(session.travel_dna);
  }),

  http.post("*/planning-sessions/:sessionId/futures", ({ params }) => {
    const sessionId = String(params.sessionId);
    const stored = sessions.get(sessionId);
    if (!stored) return problemResponse({ title: "Сессия не найдена", status: 404 });

    const generated = fixtureFutures(stored.input, stored.session.travel_dna.id);
    generated.forEach((future) => futures.set(future.id, future));

    return HttpResponse.json(
      completedJob("generate_futures", { kind: "futures", futures: generated }),
      { status: 202 },
    );
  }),

  http.get("*/planning-sessions/:sessionId/futures", ({ params }) => {
    const sessionId = String(params.sessionId);
    const stored = sessions.get(sessionId);
    if (!stored) return problemResponse({ title: "Сессия не найдена", status: 404 });
    const generated = fixtureFutures(stored.input, stored.session.travel_dna.id);
    generated.forEach((future) => futures.set(future.id, future));
    return HttpResponse.json({ futures: generated, diversity_note: null });
  }),

  http.get("*/futures/:futureId/forecast", ({ params }) => {
    const future = futures.get(String(params.futureId));
    if (!future) return problemResponse({ title: "Future не найден", status: 404 });
    return HttpResponse.json(fixtureForecast(future));
  }),

  http.post("*/futures/:futureId/simulations", async ({ params, request }) => {
    const future = futures.get(String(params.futureId));
    if (!future) return problemResponse({ title: "Future не найден", status: 404 });

    const payload = (await request.json().catch(() => null)) as Record<string, unknown> | null;
    const instruction = typeof payload?.instruction === "string" ? payload.instruction : null;
    const adjustments = Array.isArray(payload?.adjustments) ? payload!.adjustments as { dimension: string; direction: string }[] : [];

    if (!instruction && adjustments.length === 0) {
      return problemResponse({ title: "Нечего симулировать", status: 422, detail: "Передайте adjustments или instruction." });
    }

    // One deliberate dead end so the no-solution path is reachable from the UI rather than only in theory.
    if (instruction && /невозможн|дешевле в два раза/i.test(instruction)) {
      return HttpResponse.json(
        completedJob("simulate", {
          kind: "no_solution",
          no_solution: {
            reason: "Дешевле этого уровня не выходит без отказа от моря или тишины.",
            unsatisfiable_constraints: ["total_budget"],
            nearest_alternatives: [future],
          },
        }),
        { status: 202 },
      );
    }

    const child = simulatedChild(future, adjustments.map((a) => a.dimension));
    futures.set(child.id, child);
    return HttpResponse.json(completedJob("simulate", { kind: "future", future: child }), { status: 202 });
  }),

  http.post("*/futures/:futureId/forecast/risks/:riskId/mitigations/:mitigationId", ({ params }) => {
    const future = futures.get(String(params.futureId));
    if (!future) return problemResponse({ title: "Future не найден", status: 404 });

    const child = mitigatedChild(future, String(params.riskId));
    futures.set(child.id, child);
    return HttpResponse.json(completedJob("apply_mitigation", { kind: "future", future: child }), { status: 202 });
  }),

  http.get("*/futures/:futureId", ({ params }) => {
    const future = futures.get(String(params.futureId));
    if (!future) return problemResponse({ title: "Future не найден", status: 404 });
    return HttpResponse.json(future);
  }),

  http.get("*/jobs/:jobId", ({ params }) => {
    const job = jobs.get(String(params.jobId));
    if (!job) return problemResponse({ title: "Задача не найдена", status: 404 });
    return HttpResponse.json(job);
  }),
];

// The mock settles jobs immediately. Polling still has to work, so the job is stored and readable by id —
// a client that skipped the poll would pass here and fail against the real backend.
function completedJob(kind: Job["kind"], result: Job["result"]): Job {
  const job: Job = {
    id: jobId(nextJobNumber++),
    status: "succeeded",
    kind,
    created_at: "2026-08-28T09:05:00Z",
    result,
    error: null,
  };
  jobs.set(job.id, job);
  return job;
}

function jobId(sequence: number) {
  return `9${sequence.toString(16).padStart(7, "0")}${SESSION_ID.slice(8)}`;
}


function createSessionId(sequence: number) {
  if (sequence === 1) return SESSION_ID;
  return `${sequence.toString(16).padStart(8, "0")}${SESSION_ID.slice(8)}`;
}

function travelDnaVersionId(sessionId: string, version: number) {
  // Keep IDs UUID-shaped and derive them from both session and version.
  return `${sessionId.slice(0, -12)}${version.toString(16).padStart(12, "0")}`;
}

function upsertTravelDnaElements(
  current: TravelDnaElement[],
  updates: TravelDnaElementInput[],
): TravelDnaElement[] {
  const updatesByDimension = new Map(updates.map((element) => [element.dimension, element]));
  const result = current.map((element) => {
    const update = updatesByDimension.get(element.dimension);
    if (!update) return element;
    return { ...update, provenance: "confirmed" as const, confidence: 1 };
  });

  for (const update of updates) {
    if (!current.some((element) => element.dimension === update.dimension)) {
      result.push({ ...update, provenance: "confirmed", confidence: 1 });
    }
  }

  return result;
}

function fixtureFutures(input: DreamInput, travelDnaVersionId: string): Future[] {
  const checkIn = input.date_window.earliest;
  const checkOut = addDays(checkIn, input.date_window.nights_min);
  const observedAt = "2026-08-28T08:30:00Z";
  const makeLeg = (origin: string, destination: string, departAt: string, arriveAt: string): Future["logistics"]["outbound"] => ({
    origin,
    destination,
    depart_at: departAt,
    arrive_at: arriveAt,
    carrier: "Аэрофлот",
    stops: 0,
    duration_min: 180,
    as_of: observedAt,
    booking_url: "https://example.invalid/flights",
  });
  const makeFuture = (values: {
    id: string;
    cityCode: string;
    city: string;
    propertyId: string;
    property: string;
    distanceToSea: number | null;
    flight: number;
    accommodation: number;
    transfer: number;
    mobility: number;
    score: number;
    coverage: number;
    confidence: number;
    contributions: Future["match"]["contributions"];
    why: string;
    benefits: string[];
    compromises: string[];
    transferMode: Future["logistics"]["airport_transfer"]["mode"];
    transferMinutes: number;
    mobilityAssumption: string;
  }): Future => ({
    id: values.id,
    lineage_id: values.id,
    travel_dna_version_id: travelDnaVersionId,
    version: 1,
    parent_id: null,
    created_at: "2026-08-28T08:35:00Z",
    expires_at: "2026-08-28T09:35:00Z",
    destination: { city_code: values.cityCode, name: values.city, country: "Россия" },
    check_in: checkIn,
    check_out: checkOut,
    accommodation: {
      catalogue_id: values.propertyId,
      name: values.property,
      room_name: "Стандартный номер",
      handoff_url: "https://example.invalid/hotels",
      distance_to_sea_m: values.distanceToSea,
      distance_to_centre_m: 1800,
      cancellation: { refundable: true, free_until: null, summary: "Бесплатная отмена до заезда" },
    },
    logistics: {
      outbound: makeLeg(input.origin, values.cityCode, `${checkIn}T09:00:00Z`, `${checkIn}T12:00:00Z`),
      inbound: makeLeg(values.cityCode, input.origin, `${checkOut}T15:00:00Z`, `${checkOut}T18:00:00Z`),
      airport_transfer: { mode: values.transferMode, duration_min: values.transferMinutes, note: "Время рассчитано по расстоянию до аэропорта." },
      local_mobility: { assumption: values.mobilityAssumption, walkable: values.transferMode !== "private" },
    },
    price: {
      total: money(values.flight + values.accommodation + values.transfer + values.mobility),
      components: [
        { kind: "travel", amount: money(values.flight), fulfilment: "estimate", source: "Ignav · кэш рынка", handoff_url: "https://example.invalid/flights", as_of: observedAt },
        { kind: "accommodation", amount: money(values.accommodation), fulfilment: "modeled", source: "Supply · модель на базе наблюдаемого уровня", handoff_url: "https://example.invalid/hotels", as_of: null },
        { kind: "transfer", amount: money(values.transfer), fulfilment: "modeled", source: "Supply · модель трансфера", handoff_url: null, as_of: null },
        { kind: "local_mobility", amount: money(values.mobility), fulfilment: "modeled", source: "Supply · допущение мобильности", handoff_url: null, as_of: null },
      ],
    },
    match: {
      score: values.score,
      coverage: values.coverage,
      confidence: values.confidence,
      contributions: values.contributions,
      unscored_dimensions: [{ dimension: "food_quality", reason: "В fixture нет независимых отзывов о качестве еды." }],
    },
    why_this_exists: values.why,
    benefits: values.benefits,
    compromises: values.compromises,
    delta: null,
    forecast_summary: [],
  });

  return [
    makeFuture({ id: "6b5a1dd0-12d9-4bbf-8dc5-4d1bdfd52a01", cityCode: "AER", city: "Сочи", propertyId: "prop-sochi-sea", property: "Маяк у моря", distanceToSea: 180, flight: 92_000_00, accommodation: 54_000_00, transfer: 4_500_00, mobility: 2_500_00, score: 0.88, coverage: 0.85, confidence: 0.78, contributions: contributions([ ["sea_access", 0.95, 0.27, 0.26, "До моря 180 м"], ["walkability", 0.82, 0.21, 0.17, "Большинство нужного — пешком"], ["quiet", 0.62, 0.18, 0.11, "Тихая сторона района, но рядом сезонный поток"] ]), why: "Максимально близко к морю и городской еде — лучший общий баланс.", benefits: ["Море в нескольких минутах пешком", "Кафе и магазины рядом"], compromises: ["Летом здесь заметно люднее"], transferMode: "shared", transferMinutes: 35, mobilityAssumption: "Основное — пешком, две поездки на такси" }),
    makeFuture({ id: "6b5a1dd0-12d9-4bbf-8dc5-4d1bdfd52a02", cityCode: "AER", city: "Сочи", propertyId: "prop-sochi-quiet", property: "Садовый дом", distanceToSea: 1200, flight: 92_000_00, accommodation: 43_000_00, transfer: 4_500_00, mobility: 2_500_00, score: 0.83, coverage: 0.82, confidence: 0.75, contributions: contributions([ ["quiet", 0.91, 0.27, 0.25, "Дальше от главной дороги"], ["sea_access", 0.56, 0.21, 0.12, "До берега около 15 минут"], ["walkability", 0.68, 0.18, 0.12, "До центра можно дойти, часть маршрута с уклоном"] ]), why: "Экономит на локации и даёт больше тишины, сохраняя тот же аэропорт.", benefits: ["Спокойнее вечером", "Ниже стоимость проживания"], compromises: ["До моря дальше", "Понадобится больше ходить"], transferMode: "shared", transferMinutes: 35, mobilityAssumption: "Пешком до центра, такси до моря" }),
    makeFuture({ id: "6b5a1dd0-12d9-4bbf-8dc5-4d1bdfd52a03", cityCode: "MRV", city: "Кисловодск", propertyId: "prop-mrv-mountain", property: "Тихий парк-отель", distanceToSea: null, flight: 68_000_00, accommodation: 38_000_00, transfer: 3_500_00, mobility: 5_000_00, score: 0.76, coverage: 0.64, confidence: 0.61, contributions: contributions([ ["quiet", 0.94, 0.27, 0.25, "Парк и низкая дорожная нагрузка"], ["nature_vs_city", 0.88, 0.21, 0.18, "Большая часть маршрутов проходит через парк"], ["transfer_simplicity", 0.61, 0.18, 0.11, "Трансфер длиннее, чем к побережью"] ]), why: "Другой ландшафт и тишина для тех, кому важнее перезагрузка, чем море.", benefits: ["Парк начинается рядом", "Самый доступный перелёт"], compromises: ["Моря нет", "Трансфер займёт больше времени"], transferMode: "shared", transferMinutes: 65, mobilityAssumption: "Пешком по курортной части, такси до дальних мест" }),
  ];
}

function contributions(values: Array<[string, number, number, number, string]>): Future["match"]["contributions"] {
  return values.map(([dimension, satisfaction, weight, contribution, explanation]) => ({
    dimension: dimension as Future["match"]["contributions"][number]["dimension"], satisfaction, weight, contribution, confidence: 0.8, explanation,
  }));
}

function money(amountMinor: number): Money {
  return { amount_minor: amountMinor, currency: "RUB" };
}

function addDays(date: string, days: number) {
  const result = new Date(`${date}T00:00:00Z`);
  result.setUTCDate(result.getUTCDate() + days);
  return result.toISOString().slice(0, 10);
}

function isDreamInput(value: unknown): value is DreamInput {
  if (!isRecord(value)) return false;
  const allowedKeys = ["dream_text", "origin", "date_window", "party", "budget_total"];
  if (Object.keys(value).some((key) => !allowedKeys.includes(key))) return false;

  const dateWindow = value.date_window;
  const party = value.party;
  return (
    typeof value.dream_text === "string" &&
    value.dream_text.trim().length >= 1 &&
    value.dream_text.length <= 4000 &&
    typeof value.origin === "string" &&
    /^[A-Z]{3}$/.test(value.origin) &&
    isRecord(dateWindow) &&
    Object.keys(dateWindow).length === 4 &&
    isIsoDate(dateWindow.earliest) &&
    isIsoDate(dateWindow.latest) &&
    isPositiveInteger(dateWindow.nights_min) &&
    isPositiveInteger(dateWindow.nights_max) &&
    isRecord(party) &&
    Object.keys(party).length === 1 &&
    (party.adults === 1 || party.adults === 2) &&
    isOptionalBudget(value.budget_total)
  );
}

function problemResponse(problem: ProblemDetails) {
  return HttpResponse.json(problem, {
    status: problem.status ?? 422,
    headers: { "Content-Type": "application/problem+json" },
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isPositiveInteger(value: unknown) {
  return typeof value === "number" && Number.isInteger(value) && value >= 1;
}

function isIsoDate(value: unknown) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(parsed.valueOf()) && parsed.toISOString().slice(0, 10) === value;
}

function isOptionalBudget(value: unknown) {
  if (value === undefined || value === null) return true;
  return (
    isRecord(value) &&
    Object.keys(value).length === 2 &&
    Number.isInteger(value.amount_minor) &&
    value.currency === "RUB"
  );
}

// A forecast that exercises the honest cases on purpose: one inference-grade risk with a mitigation, one
// derived metric, and five types reported as unassessed with a reason. Four of the nine can only be evidenced
// by review text, which this product does not have (C-05) — the UI has to make that visible, so the mock
// must produce it.
function fixtureForecast(future: Future): Forecast {
  const nearSea = (future.accommodation.distance_to_sea_m ?? 9_999) < 400;

  return {
    future_id: future.id,
    generated_at: "2026-08-28T09:10:00Z",
    risks: [
      {
        id: `${future.id}-night-noise`,
        risk_type: "night_noise",
        severity: nearSea ? "high" : "medium",
        confidence: 0.5,
        claim_kind: "model_inference",
        affected_dimension: "quiet",
        statement:
          "Дорога класса primary проходит в 180 м — ближе 300 м, с которых шум такой дороги обычно слышен. " +
          "Это вывод из расстояния: шум не измерялся, и о том, куда выходят окна номера, данных нет.",
        evidence: [
          {
            source: "geo",
            excerpt: "Ближайшая крупная дорога: 180 м, класс primary (порог для этого класса — 300 м).",
            observed_at: "2026-08-20",
            count: null,
          },
        ],
        mitigations: [
          {
            id: `${future.id}-quiet-room`,
            description: "Объект на квартал дальше от дороги",
            price_change: money(340_000),
            severity_after: "low",
          },
        ],
      },
      {
        id: `${future.id}-weather`,
        risk_type: "weather_mismatch",
        severity: "low",
        confidence: 0.75,
        claim_kind: "derived_metric",
        affected_dimension: "climate_warm",
        statement: "Средняя температура в эти даты 24 °C — внутри полосы, которую вы назвали тёплой.",
        evidence: [
          { source: "weather", excerpt: "Норма месяца: 24 °C, море 23 °C.", observed_at: "2026-08-01", count: null },
        ],
      },
    ],
    coverage: [
      { risk_type: "night_noise", assessed: true },
      { risk_type: "weather_mismatch", assessed: true },
      { risk_type: "walkability", assessed: true },
      { risk_type: "transfer_difficulty", assessed: true },
      { risk_type: "crowds", assessed: false, reason: "Нужны отзывы: источника с текстом отзывов нет" },
      { risk_type: "construction", assessed: false, reason: "Нужны отзывы: источника с текстом отзывов нет" },
      { risk_type: "weak_transport", assessed: false, reason: "Нужны отзывы: источника с текстом отзывов нет" },
      { risk_type: "room_location_mismatch", assessed: false, reason: "Нужны отзывы: источника с текстом отзывов нет" },
      { risk_type: "seasonal_closure", assessed: false, reason: "Нужны отзывы: источника с текстом отзывов нет" },
    ],
  };
}

// A simulated child. Immutable by construction: a new id, parent_id set, and a delta whose items sum exactly
// to the price change — the arithmetic the UI is meant to show has to add up in the fixtures too.
function simulatedChild(parent: Future, dimensions: string[]): Future {
  const relaxed = (dimensions[0] ?? "sea_access") as Delta["items"][number]["relaxed_dimension"];
  const accommodationSaving = 830_000;
  const flightSaving = 210_000;
  const change = -(accommodationSaving + flightSaving);

  const components = parent.price.components.map((component) => {
    if (component.kind === "accommodation") {
      return { ...component, amount: money(component.amount.amount_minor - accommodationSaving) };
    }
    if (component.kind === "travel") {
      return { ...component, amount: money(component.amount.amount_minor - flightSaving) };
    }
    return component;
  });

  const total = money(components.reduce((sum, component) => sum + component.amount.amount_minor, 0));
  const matchAfter = Number((parent.match.score - 0.02).toFixed(2));

  return {
    ...parent,
    id: `${parent.id.slice(0, -2)}${(parent.version + 1).toString().padStart(2, "0")}`,
    version: parent.version + 1,
    parent_id: parent.id,
    price: { total, components },
    match: { ...parent.match, score: matchAfter },
    why_this_exists: "Дешевле за счёт наименее важного для вас компромисса",
    compromises: [...parent.compromises, "До моря дальше на 400 м"],
    delta: {
      from_future_id: parent.id,
      price_before: parent.price.total,
      price_after: total,
      price_change: money(change),
      items: [
        { description: "Объект дальше от моря", amount: money(-accommodationSaving), relaxed_dimension: relaxed },
        { description: "Вылет на два дня позже", amount: money(-flightSaving), relaxed_dimension: "dates" },
      ],
      match_before: parent.match.score,
      match_after: matchAfter,
      dimension_changes: [
        { dimension: "sea_access", change: "worsened" },
        { dimension: "total_budget", change: "improved" },
        { dimension: "quiet", change: "unchanged" },
      ],
      new_risks: [],
      resolved_risks: [],
      explanation: "Снизили цену там, где вам менее важно: расстояние до моря и даты.",
    },
  };
}

// Applying a mitigation is a simulation too (DEC-022 / the Forecast doc): it produces a new version with a
// delta, not an edit in place. Here it costs money and removes the risk it was proposed for.
function mitigatedChild(parent: Future, riskId: string): Future {
  const cost = 340_000;
  const components = parent.price.components.map((component) => (
    component.kind === "accommodation"
      ? { ...component, amount: money(component.amount.amount_minor + cost) }
      : component
  ));
  const total = money(components.reduce((sum, component) => sum + component.amount.amount_minor, 0));
  const matchAfter = Number((parent.match.score + 0.01).toFixed(2));

  return {
    ...parent,
    id: `${parent.id.slice(0, -2)}${(parent.version + 1).toString().padStart(2, "0")}`,
    version: parent.version + 1,
    parent_id: parent.id,
    price: { total, components },
    match: { ...parent.match, score: matchAfter },
    why_this_exists: "То же самое, но без риска ночного шума",
    delta: {
      from_future_id: parent.id,
      price_before: parent.price.total,
      price_after: total,
      price_change: money(cost),
      items: [{ description: "Объект на квартал дальше от дороги", amount: money(cost), relaxed_dimension: null }],
      match_before: parent.match.score,
      match_after: matchAfter,
      dimension_changes: [{ dimension: "quiet", change: "improved" }],
      new_risks: [],
      resolved_risks: [{ id: riskId, risk_type: "night_noise", severity: "high" }],
      explanation: "Риск ночного шума устранён; это стоит 3 400 ₽.",
    },
  };
}
