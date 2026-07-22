import { setupServer } from "msw/node";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import { ElsewhereClient } from "../generated/client";
import { handlers } from "./handlers";

const server = setupServer(...handlers);

beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

describe("fixture futures journey", () => {
  it("returns three complete Future cards after generation", async () => {
    const client = new ElsewhereClient("http://localhost:3000");
    const session = await client.createPlanningSession({
      dream_text: "Тихо у моря",
      origin: "MOW",
      date_window: { earliest: "2026-09-10", latest: "2026-09-24", nights_min: 6, nights_max: 8 },
      party: { adults: 2 },
    });

    const result = await client.generateFutures(session.id);

    expect(result.futures).toHaveLength(3);
    expect(new Set(result.futures.map((future) => future.destination.city_code))).toEqual(new Set(["AER", "MRV"]));
    result.futures.forEach((future) => {
      expect(future.logistics.outbound).toBeDefined();
      expect(future.logistics.inbound).toBeDefined();
      expect(future.price.components.map((component) => component.fulfilment)).toEqual(
        expect.arrayContaining(["estimate", "modeled"]),
      );
      expect(future.match.contributions.length).toBeGreaterThan(0);
      expect(future.match.unscored_dimensions.length).toBeGreaterThan(0);
      expect(future.benefits.length).toBeGreaterThan(0);
      expect(future.compromises.length).toBeGreaterThan(0);
    });
  });

  it("applies sequential partial DNA patches as upserts with distinct deterministic version IDs", async () => {
    const client = new ElsewhereClient("http://localhost:3000");
    const session = await client.createPlanningSession({
      dream_text: "Тихо у моря",
      origin: "MOW",
      date_window: { earliest: "2026-09-10", latest: "2026-09-24", nights_min: 6, nights_max: 8 },
      party: { adults: 2 },
    });

    const firstUpdate = await client.updateTravelDna(session.id, [{
      dimension: "quiet",
      kind: "preference",
      target: 0.95,
      weight: 0.9,
    }]);
    const secondUpdate = await client.updateTravelDna(session.id, [{
      dimension: "dates",
      kind: "hard_constraint",
      target: { earliest: "2026-10-01", latest: "2026-10-15", nights_min: 7, nights_max: 9 },
      weight: null,
    }]);

    expect(firstUpdate.version).toBe(2);
    expect(secondUpdate.version).toBe(3);
    expect(firstUpdate.id).not.toBe(secondUpdate.id);
    expect(firstUpdate.id).toBe(`${session.id.slice(0, -12)}000000000002`);
    expect(secondUpdate.id).toBe(`${session.id.slice(0, -12)}000000000003`);
    expect(secondUpdate.elements).toHaveLength(session.travel_dna.elements.length);
    expect(secondUpdate.elements.find((element) => element.dimension === "quiet")?.target).toBe(0.95);
    expect(secondUpdate.elements.find((element) => element.dimension === "dates")?.target).toEqual({
      earliest: "2026-10-01",
      latest: "2026-10-15",
      nights_min: 7,
      nights_max: 9,
    });
  });

  it("keeps sessions isolated and points futures at each session's current DNA version", async () => {
    const client = new ElsewhereClient("http://localhost:3000");
    const input = {
      dream_text: "Тихо у моря",
      origin: "MOW",
      date_window: { earliest: "2026-09-10", latest: "2026-09-24", nights_min: 6, nights_max: 8 },
      party: { adults: 2 as const },
    };

    const firstSession = await client.createPlanningSession(input);
    const secondSession = await client.createPlanningSession(input);
    const firstVersion = await client.updateTravelDna(firstSession.id, [{
      dimension: "quiet",
      kind: "preference",
      target: 0.1,
      weight: 0.2,
    }]);
    const secondVersion = await client.updateTravelDna(secondSession.id, [{
      dimension: "quiet",
      kind: "preference",
      target: 0.9,
      weight: 0.8,
    }]);
    const firstFutures = await client.generateFutures(firstSession.id);
    const secondFutures = await client.generateFutures(secondSession.id);

    expect(firstSession.id).not.toBe(secondSession.id);
    expect(firstVersion.id).not.toBe(secondVersion.id);
    expect(firstVersion.version).toBe(2);
    expect(secondVersion.version).toBe(2);
    expect(firstFutures.futures[0].travel_dna_version_id).toBe(firstVersion.id);
    expect(secondFutures.futures[0].travel_dna_version_id).toBe(secondVersion.id);
    expect(firstVersion.id).toMatch(/^[0-9a-f-]{36}$/);

    await expect(client.updateTravelDna("missing-session", [])).rejects.toMatchObject({ status: 404 });
  });
});
