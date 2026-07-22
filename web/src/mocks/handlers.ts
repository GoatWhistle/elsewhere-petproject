// Contract-shaped development responses for the frozen OpenAPI resources.
import { http, HttpResponse } from "msw";
import type { DreamInput, PlanningSession, ProblemDetails } from "../generated/client";

const SESSION_ID = "03571d18-8537-48aa-995c-fc0f9a41ba51";
const DNA_ID = "a3fe8185-7565-4f9f-84c7-b12d7c7c62d8";

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

    const session: PlanningSession = {
      id: SESSION_ID,
      created_at: "2026-08-28T09:00:00Z",
      dream_text: payload.dream_text,
      travel_dna: {
        id: DNA_ID,
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

    return HttpResponse.json(session, { status: 201 });
  }),

  http.post("*/planning-sessions/:sessionId/futures", () =>
    HttpResponse.json(
      { id: "fixture-generation", status: "succeeded", result_url: `/planning-sessions/${SESSION_ID}/futures` },
      { status: 202 },
    )),

  http.get("*/planning-sessions/:sessionId/futures", () =>
    HttpResponse.json({ futures: [], diversity_note: "Варианты появятся после реализации D-3." })),
];

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
