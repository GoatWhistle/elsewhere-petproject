import { act, render, screen, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Future } from "../generated/client";
import { TripPlan } from "./TripPlan";

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
    handoff_url: "https://example.test/property/prop-sochi-sea",
    cancellation: { refundable: true, free_until: "2026-09-03", summary: "Бесплатная отмена до 3 сентября" },
    distance_to_sea_m: 180,
    distance_to_centre_m: 2400,
  },
  logistics: {
    outbound: {
      origin: "MOW", destination: "AER", depart_at: "2026-09-10T09:00:00Z", arrive_at: "2026-09-10T12:00:00Z",
      carrier: "Аэрофлот", stops: 0, duration_min: 180, as_of: "2026-08-28T08:30:00Z",
      booking_url: "https://example.test/fare/outbound",
    },
    inbound: {
      origin: "AER", destination: "MOW", depart_at: "2026-09-17T15:00:00Z", arrive_at: "2026-09-17T18:00:00Z",
      carrier: "Аэрофлот", stops: 1, duration_min: 245, as_of: "2026-08-28T08:30:00Z", booking_url: null,
    },
    airport_transfer: { mode: "shared", duration_min: 35, note: "Расстояние до аэропорта 24 км" },
    local_mobility: { assumption: "Основное — пешком, пара такси за поездку", walkable: true },
  },
  price: {
    total: { amount_minor: 16900000, currency: "RUB" },
    components: [
      { kind: "travel", amount: { amount_minor: 9200000, currency: "RUB" }, fulfilment: "estimate", source: "Ignav", as_of: "2026-08-28T08:30:00Z" },
      { kind: "accommodation", amount: { amount_minor: 5400000, currency: "RUB" }, fulfilment: "modeled", source: "Supply", as_of: null },
      { kind: "transfer", amount: { amount_minor: 1500000, currency: "RUB" }, fulfilment: "modeled", source: "Planning", as_of: null },
      { kind: "local_mobility", amount: { amount_minor: 800000, currency: "RUB" }, fulfilment: "modeled", source: "Planning", as_of: null },
    ],
  },
  match: {
    score: 0.88,
    coverage: 0.85,
    confidence: 0.78,
    contributions: [
      { dimension: "sea_access", satisfaction: 0.95, weight: 0.27, contribution: 0.26, confidence: 0.8, explanation: "До моря 180 м" },
    ],
    unscored_dimensions: [{ dimension: "food_quality", reason: "Нет независимых отзывов" }],
  },
  why_this_exists: "Лучший общий баланс.",
  benefits: ["Море рядом"],
  compromises: ["Летом люднее", "Пересадка на обратном пути"],
  delta: null,
  forecast_summary: [],
};

function rowFor(name: RegExp) {
  const header = screen.getByRole("rowheader", { name });
  const row = header.closest("tr");
  if (!row) throw new Error(`Строка «${name}» не найдена`);
  return row;
}

describe("TripPlan", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-08-28T09:05:00Z"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("states the origin of every cost component", () => {
    render(<TripPlan future={future} />);

    const flight = rowFor(/Перелёт/);
    expect(within(flight).getByText("наблюдаемая оценка")).toBeVisible();
    expect(within(flight).getByText(/Ignav/)).toHaveTextContent(/наблюдение на .*UTC/);
    expect(within(flight).getByText(/92\s*000\s*₽/)).toBeVisible();

    const stay = rowFor(/Проживание/);
    expect(within(stay).getByText("моделируемая часть")).toBeVisible();
    expect(within(stay).getByText(/Сезонный коэффициент мы не наблюдали/)).toBeVisible();
    expect(within(stay).getByText(/54\s*000\s*₽/)).toBeVisible();

    const transfer = rowFor(/Трансфер/);
    expect(within(transfer).getByText("моделируемая часть")).toBeVisible();
    expect(within(transfer).getByText(/15\s*000\s*₽/)).toBeVisible();

    const mobility = rowFor(/Передвижение на месте/);
    expect(within(mobility).getByText("моделируемая часть")).toBeVisible();
    expect(within(mobility).getByText(/допущение/)).toBeVisible();
    expect(within(mobility).getByText(/8\s*000\s*₽/)).toBeVisible();

    // DEC-029: only the base was observed. The rate is never described as calibrated on observed prices.
    expect(screen.queryByText(/калибр/i)).not.toBeInTheDocument();
  });

  it("presents the total as an estimate with its observed/modeled split", () => {
    render(<TripPlan future={future} />);

    const total = rowFor(/Оценка всей поездки/);
    expect(within(total).getByText(/169\s*000\s*₽/)).toBeVisible();
    expect(within(total).getByText(/оценка, не оферта/)).toBeVisible();
    expect(screen.getByText(/наблюдаемые цены/)).toHaveTextContent(/92\s*000\s*₽/);
    expect(screen.getByText(/наблюдаемые цены/)).toHaveTextContent(/77\s*000\s*₽/);
    expect(screen.getByText(/Итог — оценка расходов/)).toBeVisible();
  });

  it("says nothing that implies a reservation exists", () => {
    const { container } = render(<TripPlan future={future} />);

    expect(screen.getByText(/Elsewhere ничего не бронирует и не принимает оплату/)).toBeVisible();
    expect(container.textContent).not.toMatch(/подтвержд/i);
    expect(container.textContent).not.toMatch(/забронирован/i);
    expect(container.textContent).not.toMatch(/номер (брони|заказа)/i);
    expect(screen.queryByRole("link", { name: /Забронировать|Купить|Оплатить/ })).not.toBeInTheDocument();

    const handoff = screen.getByRole("link", { name: /Посмотреть этот рейс у поставщика/ });
    expect(handoff).toHaveAttribute("href", "https://example.test/fare/outbound");
    expect(screen.getByText(/удобство для того, кто решил ехать/)).toBeVisible();
  });

  it("does not render a total without its origin split", () => {
    const withoutComponents = { ...future, price: { ...future.price, components: [] } };
    render(<TripPlan future={withoutComponents} />);

    expect(screen.getByText(/Итог не показываем без разбиения/)).toBeVisible();
    expect(screen.queryByText(/169\s*000\s*₽/)).not.toBeInTheDocument();
  });

  it("lays the trip out in the order it happens, with times in the timezone it labels", () => {
    render(<TripPlan future={future} />);

    const headings = screen.getAllByRole("heading", { level: 3 }).map((heading) => heading.textContent);
    expect(headings).toEqual([
      "Как вы туда добираетесь",
      "Где вы живёте и какие ночи",
      "Из аэропорта до места и обратно",
      "Как вы передвигаетесь на месте",
      "Во что это обойдётся",
      "На что вы согласились, выбрав этот вариант",
    ]);

    const outbound = screen.getByRole("region", { name: /Туда: MOW → AER/ });
    expect(within(outbound).getByText(/10 сент.*09:00 UTC/)).toBeVisible();
    expect(within(outbound).getByText(/3 ч · без пересадок/)).toBeVisible();

    const inbound = screen.getByRole("region", { name: /Обратно: AER → MOW/ });
    expect(within(inbound).getByText(/4 ч 5 мин · 1 пересадка/)).toBeVisible();

    expect(screen.getByText(/Время рейсов — UTC/)).toBeVisible();
    expect(screen.getAllByText("7 ночей").length).toBeGreaterThan(0);
    expect(screen.getByText("сборный")).toBeVisible();
    expect(screen.getByText("35 мин")).toBeVisible();
    expect(screen.getByText("Основное — пешком, пара такси за поездку")).toBeVisible();
  });

  it("shows the compromises the user accepted by choosing this Future", () => {
    render(<TripPlan future={future} />);

    expect(screen.getByText("Лучший общий баланс.")).toBeVisible();
    expect(screen.getByText("Летом люднее")).toBeVisible();
    expect(screen.getByText("Пересадка на обратном пути")).toBeVisible();
    expect(screen.getByText("Море рядом")).toBeVisible();
  });

  it("marks the plan outdated once it passes expires_at", () => {
    vi.setSystemTime(new Date("2026-08-28T09:36:00Z"));
    render(<TripPlan future={future} />);

    expect(screen.getByText(/План устарел · расчёт создан 1 ч 1 мин назад/)).toBeVisible();
    expect(screen.getByText(/запросите пересчёт/)).toBeVisible();
    expect(screen.queryByText(/действует до/)).not.toBeInTheDocument();
  });

  it("marks a plan outdated while it sits on screen", () => {
    vi.setSystemTime(new Date("2026-08-28T09:34:59Z"));
    render(<TripPlan future={future} />);

    expect(screen.getByText(/План актуален · расчёт создан 59 мин назад/)).toBeVisible();

    act(() => {
      vi.advanceTimersByTime(1_000);
    });

    expect(screen.getByText(/План устарел/)).toBeVisible();
    expect(screen.queryByText(/План актуален/)).not.toBeInTheDocument();
  });
});
