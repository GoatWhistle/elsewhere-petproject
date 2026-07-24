import { act, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Future } from "../generated/client";
import { FuturesView } from "./FuturesView";

const future: Future = {
  id: "6b5a1dd0-12d9-4bbf-8dc5-4d1bdfd52a01",
  lineage_id: "6b5a1dd0-12d9-4bbf-8dc5-4d1bdfd52a01",
  travel_dna_version_id: "a3fe8185-7565-4f9f-84c7-b12d7c7c62d8",
  version: 1,
  parent_id: null,
  created_at: "2026-08-28T08:35:00Z",
  expires_at: "2026-08-28T09:35:00Z",
  destination: { city_code: "AER", name: "Сочи", country: "Россия" },
  check_in: "2026-09-10",
  check_out: "2026-09-17",
  accommodation: {
    catalogue_id: "prop-sochi-sea",
    name: "Маяк у моря",
    room_name: "Стандартный номер",
    distance_to_sea_m: 180,
  },
  logistics: {
    outbound: {
      origin: "MOW", destination: "AER", depart_at: "2026-09-10T09:00:00Z", arrive_at: "2026-09-10T12:00:00Z",
      carrier: "Аэрофлот", stops: 0, duration_min: 180, as_of: "2026-08-28T08:30:00Z", booking_url: null,
    },
    inbound: {
      origin: "AER", destination: "MOW", depart_at: "2026-09-17T15:00:00Z", arrive_at: "2026-09-17T18:00:00Z",
      carrier: "Аэрофлот", stops: 0, duration_min: 180, as_of: "2026-08-28T08:30:00Z", booking_url: null,
    },
    airport_transfer: { mode: "shared", duration_min: 35, note: "Расстояние до аэропорта" },
    local_mobility: { assumption: "Основное — пешком", walkable: true },
  },
  price: {
    total: { amount_minor: 15300000, currency: "RUB" },
    components: [
      { kind: "travel", amount: { amount_minor: 9200000, currency: "RUB" }, fulfilment: "estimate", source: "Ignav", as_of: "2026-08-28T08:30:00Z" },
      { kind: "accommodation", amount: { amount_minor: 5400000, currency: "RUB" }, fulfilment: "modeled", source: "Supply", as_of: null },
    ],
  },
  match: {
    score: 0.88,
    coverage: 0.85,
    confidence: 0.78,
    contributions: [
      { dimension: "sea_access", satisfaction: 0.95, weight: 0.27, contribution: 0.26, confidence: 0.8, explanation: "До моря 180 м" },
      { dimension: "quiet", satisfaction: 0.62, weight: 0.18, contribution: 0.11, confidence: 0.6, explanation: "Есть сезонный поток" },
    ],
    unscored_dimensions: [{ dimension: "food_quality", reason: "Нет независимых отзывов" }],
  },
  why_this_exists: "Лучший общий баланс.",
  benefits: ["Море рядом"],
  compromises: ["Летом люднее"],
  delta: null,
  forecast_summary: [],
};

describe("FuturesView", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-08-28T09:05:00Z"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("keeps Match and total price tied to their evidence", () => {
    render(<FuturesView futures={[future]} />);

    expect(screen.getByText("88%").parentElement).toHaveTextContent("Покрытие 85% · уверенность 78%");
    expect(screen.getByText("Почему такой Match")).toBeVisible();
    expect(screen.getAllByText("До моря 180 м").length).toBe(2);
    expect(screen.getByText(/наблюдаемая оценка/)).toBeVisible();
    expect(screen.getByText(/моделируемая часть/)).toBeVisible();
    expect(screen.getByText(/Ignav/)).toBeVisible();
    expect(screen.getByText("MOW → AER")).toBeVisible();
    expect(screen.getAllByText(/UTC/).length).toBeGreaterThan(0);
    expect(screen.getByText(/План актуален · расчёт создан 30 мин назад/)).toBeVisible();
    expect(screen.getByRole("heading", { name: "Что мы пока не знаем" })).toBeVisible();
    expect(screen.getByText(/Нет независимых отзывов/)).toBeVisible();
  });

  it("does not show an unsubstantiated score or total", () => {
    const incomplete = {
      ...future,
      price: { ...future.price, components: [] },
      match: { ...future.match, contributions: [] },
    };
    render(<FuturesView futures={[incomplete]} />);

    expect(screen.getByText("Нет данных")).toBeVisible();
    expect(screen.getByText("Итого пока неизвестно")).toBeVisible();
    expect(screen.getByText(/Match нельзя показать/)).toBeVisible();
    expect(screen.getByText(/Итог не показываем/)).toBeVisible();
  });

  it("shows the total when every component has fulfilment, including modeled-only prices", () => {
    const modeledOnly = {
      ...future,
      price: {
        ...future.price,
        components: future.price.components.map((component) => ({ ...component, fulfilment: "modeled" as const })),
      },
    };
    render(<FuturesView futures={[modeledOnly]} />);

    expect(screen.getByRole("heading", { name: /153\s*000\s*₽/ })).toBeVisible();
    expect(screen.queryByText(/Итого пока неизвестно/)).not.toBeInTheDocument();
  });

  it("shows only the two largest contributions inline and keeps the full breakdown in details", () => {
    const withMoreContributions = {
      ...future,
      match: {
        ...future.match,
        contributions: [
          ...future.match.contributions,
          { dimension: "food_quality" as const, satisfaction: 0.4, weight: 0.1, contribution: 0.05, confidence: 0.5, explanation: "Еда" },
          { dimension: "nightlife" as const, satisfaction: 0.2, weight: 0.1, contribution: -0.03, confidence: 0.5, explanation: "Ночная жизнь" },
        ],
      },
    };
    render(<FuturesView futures={[withMoreContributions]} />);

    const preview = screen.getByRole("region", { name: "Главные вклады" });
    expect(within(preview).getByText("Море")).toBeVisible();
    expect(within(preview).getByText("Тишина")).toBeVisible();
    expect(within(preview).queryByText("Еда")).not.toBeInTheDocument();
    expect(within(preview).queryByText("Ночная жизнь")).not.toBeInTheDocument();
    expect(preview.querySelectorAll(".contribution-row")).toHaveLength(2);
    expect(document.querySelectorAll(".evidence-details .contribution-row")).toHaveLength(4);
  });

  it("updates the stale status when the mounted plan expires", () => {
    vi.setSystemTime(new Date("2026-08-28T09:34:59Z"));
    render(<FuturesView futures={[future]} />);

    expect(screen.getByText(/План актуален/)).toBeVisible();

    act(() => {
      vi.advanceTimersByTime(1_000);
    });

    expect(screen.getByText(/План устарел/)).toBeVisible();
    expect(screen.queryByText(/План актуален/)).not.toBeInTheDocument();
  });

  it("marks a plan as expired after its expires_at", () => {
    vi.setSystemTime(new Date("2026-08-28T09:36:00Z"));
    render(<FuturesView futures={[future]} />);

    expect(screen.getByText(/План устарел · расчёт создан 1 ч 1 мин назад/)).toBeVisible();
    expect(screen.queryByText(/действует до/)).not.toBeInTheDocument();
  });
});
