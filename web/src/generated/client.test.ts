import { afterEach, describe, expect, it, vi } from "vitest";
import { ElsewhereClient } from "./client";
import type { DreamInput, PlanningSession, TravelDnaElementInput } from "./client";

const input: DreamInput = {
  dream_text: "Неделя спокойствия у моря",
  origin: "MOW",
  date_window: {
    earliest: "2026-09-10",
    latest: "2026-09-24",
    nights_min: 6,
    nights_max: 8,
  },
  party: { adults: 2 },
};

const session: PlanningSession = {
  id: "03571d18-8537-48aa-995c-fc0f9a41ba51",
  created_at: "2026-08-28T09:00:00Z",
  dream_text: input.dream_text,
  travel_dna: {
    id: "a3fe8185-7565-4f9f-84c7-b12d7c7c62d8",
    version: 1,
    elements: [],
    unmatched_intent: [],
  },
  clarifications: [],
};

afterEach(() => vi.unstubAllGlobals());

describe("ElsewhereClient.createPlanningSession", () => {
  it("sends the complete DreamInput unchanged", async () => {
    const fetchMock = vi.fn<typeof fetch>(async () =>
      new Response(JSON.stringify(session), {
        status: 201,
        headers: { "Content-Type": "application/json" },
      }));
    vi.stubGlobal("fetch", fetchMock);

    const result = await new ElsewhereClient("https://api.example.test").createPlanningSession(input);

    expect(result).toEqual(session);
    expect(fetchMock).toHaveBeenCalledOnce();
    const [url, request] = fetchMock.mock.calls[0];
    expect(url).toBe("https://api.example.test/planning-sessions");
    expect(request).toMatchObject({ method: "POST", body: JSON.stringify(input) });
    expect(JSON.parse(String(request?.body))).toEqual(input);
  });

  it("exposes an application/problem+json response as ApiProblem", async () => {
    vi.stubGlobal("fetch", vi.fn(async () =>
      new Response(JSON.stringify({
        type: "https://elsewhere.example/problems/invalid-dream",
        title: "Некорректные данные",
        status: 422,
        detail: "Город вылета неизвестен.",
      }), {
        status: 422,
        headers: { "Content-Type": "application/problem+json" },
      })));

    const request = new ElsewhereClient().createPlanningSession(input);

    await expect(request).rejects.toMatchObject({
      name: "ApiProblem",
      status: 422,
      message: "Город вылета неизвестен.",
    });
  });

  it("turns a non-JSON server error into a stable ApiProblem", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("Bad gateway", { status: 502 })));

    const request = new ElsewhereClient().createPlanningSession(input);

    await expect(request).rejects.toMatchObject({
      status: 502,
      message: "Не удалось выполнить запрос",
    });
  });
});

describe("ElsewhereClient.updateTravelDna", () => {
  it("patches the complete edited element set", async () => {
    const elements: TravelDnaElementInput[] = [{
      dimension: "quiet",
      kind: "preference",
      target: "very high",
      weight: 0.9,
    }];
    const updatedDna = { ...session.travel_dna, version: 2, elements: [{
      ...elements[0], provenance: "confirmed" as const, confidence: 1,
    }] };
    const fetchMock = vi.fn<typeof fetch>(async () => new Response(JSON.stringify(updatedDna), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    }));
    vi.stubGlobal("fetch", fetchMock);

    await expect(new ElsewhereClient("https://api.example.test").updateTravelDna(session.id, elements))
      .resolves.toEqual(updatedDna);

    const [url, request] = fetchMock.mock.calls[0];
    expect(url).toBe(`https://api.example.test/planning-sessions/${session.id}/travel-dna`);
    expect(request).toMatchObject({ method: "PATCH", body: JSON.stringify({ elements }) });
  });
});
