import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import type { Delta, Future, Job, SimulationRequest } from "../generated/client";
import { SimulatorPanel } from "./SimulatorPanel";

const parent: Future = {
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
    airport_transfer: { mode: "shared", duration_min: 35 },
    local_mobility: { assumption: "Основное — пешком", walkable: true },
  },
  price: {
    total: { amount_minor: 15_300_000, currency: "RUB" },
    components: [
      { kind: "travel", amount: { amount_minor: 9_200_000, currency: "RUB" }, fulfilment: "estimate", source: "Ignav", as_of: "2026-08-28T08:30:00Z" },
      { kind: "accommodation", amount: { amount_minor: 6_100_000, currency: "RUB" }, fulfilment: "modeled", source: "Supply", as_of: null },
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

const delta: Delta = {
  from_future_id: parent.id,
  price_before: { amount_minor: 15_300_000, currency: "RUB" },
  price_after: { amount_minor: 14_260_000, currency: "RUB" },
  price_change: { amount_minor: -1_040_000, currency: "RUB" },
  items: [
    { description: "Объект дальше от моря", amount: { amount_minor: -830_000, currency: "RUB" }, relaxed_dimension: "sea_access" },
    { description: "Вылет на два дня позже", amount: { amount_minor: -210_000, currency: "RUB" }, relaxed_dimension: "dates" },
  ],
  match_before: 0.88,
  match_after: 0.86,
  dimension_changes: [
    { dimension: "sea_access", change: "worsened" },
    { dimension: "total_budget", change: "improved" },
    { dimension: "quiet", change: "unchanged" },
  ],
  new_risks: [{ id: "risk-noise", risk_type: "night_noise", severity: "high" }],
  resolved_risks: [{ id: "risk-crowds", risk_type: "crowds", severity: "medium" }],
  explanation: "Снизили цену там, где вам менее важно.",
};

const child: Future = {
  ...parent,
  id: "6b5a1dd0-12d9-4bbf-8dc5-4d1bdfd52a02",
  version: 2,
  parent_id: parent.id,
  price: {
    total: { amount_minor: 14_260_000, currency: "RUB" },
    components: [
      { kind: "travel", amount: { amount_minor: 8_990_000, currency: "RUB" }, fulfilment: "estimate", source: "Ignav", as_of: "2026-08-28T08:30:00Z" },
      { kind: "accommodation", amount: { amount_minor: 5_270_000, currency: "RUB" }, fulfilment: "modeled", source: "Supply", as_of: null },
    ],
  },
  match: { ...parent.match, score: 0.86 },
  delta,
};

function job(overrides: Partial<Job> = {}): Job {
  return {
    id: "job-1",
    status: "succeeded",
    kind: "simulate",
    created_at: "2026-08-28T08:40:00Z",
    result: { kind: "future", future: child },
    error: null,
    ...overrides,
  };
}

function renderPanel(onSimulate: (request: SimulationRequest) => Promise<Job>, onApplyResult = vi.fn()) {
  render(<SimulatorPanel future={parent} onSimulate={onSimulate} onApplyResult={onApplyResult} />);
  return { onApplyResult };
}

function moveSlider(label: string, steps: number) {
  fireEvent.change(screen.getByLabelText(label), { target: { value: String(steps) } });
}

describe("SimulatorPanel", () => {
  it("maps the cheaper↔comfortable slider onto a target-total adjustment", async () => {
    const user = userEvent.setup();
    const onSimulate = vi.fn().mockResolvedValue(job());
    renderPanel(onSimulate);

    moveSlider("Дешевле ↔ комфортнее", -1);
    await user.click(screen.getByRole("button", { name: "Пересчитать будущее" }));

    expect(onSimulate).toHaveBeenCalledWith({
      adjustments: [{ dimension: "total_budget", direction: "decrease", magnitude: 0.08 }],
      persist_to_travel_dna: false,
    });
  });

  it("scales the magnitude with the number of steps and flips the direction", async () => {
    const user = userEvent.setup();
    const onSimulate = vi.fn().mockResolvedValue(job());
    renderPanel(onSimulate);

    moveSlider("Дешевле ↔ комфортнее", 2);
    await user.click(screen.getByRole("button", { name: "Пересчитать будущее" }));

    expect(onSimulate).toHaveBeenCalledWith({
      adjustments: [{ dimension: "total_budget", direction: "increase", magnitude: 0.16 }],
      persist_to_travel_dna: false,
    });
  });

  it("moves both quiet and nightlife, and the nature/city axis, as DEC-025 defines them", async () => {
    const user = userEvent.setup();
    const onSimulate = vi.fn().mockResolvedValue(job());
    renderPanel(onSimulate);

    moveSlider("Тише ↔ живее", 1);
    moveSlider("Город ↔ природа", -1);
    await user.click(screen.getByRole("button", { name: "Пересчитать будущее" }));

    expect(onSimulate).toHaveBeenCalledWith({
      adjustments: [
        { dimension: "quiet", direction: "decrease", magnitude: 0.2 },
        { dimension: "nightlife", direction: "increase", magnitude: 0.2 },
        { dimension: "nature_vs_city", direction: "decrease", magnitude: 0.2 },
      ],
      persist_to_travel_dna: false,
    });
  });

  it("refuses to send an empty request and sends free text on its own", async () => {
    const user = userEvent.setup();
    const onSimulate = vi.fn().mockResolvedValue(job());
    renderPanel(onSimulate);

    expect(screen.getByRole("button", { name: "Пересчитать будущее" })).toBeDisabled();

    await user.type(screen.getByLabelText("Скажите словами"), "Сделай дешевле, но не испорти важное");
    await user.click(screen.getByRole("button", { name: "Применить инструкцию" }));

    expect(onSimulate).toHaveBeenCalledWith({
      instruction: "Сделай дешевле, но не испорти важное",
      persist_to_travel_dna: false,
    });
  });

  it("renders the delta items and their sum equals the displayed total change", async () => {
    const user = userEvent.setup();
    const onSimulate = vi.fn().mockResolvedValue(job());
    const { onApplyResult } = renderPanel(onSimulate);

    moveSlider("Дешевле ↔ комфортнее", -1);
    await user.click(screen.getByRole("button", { name: "Пересчитать будущее" }));

    await screen.findByRole("heading", { name: "Разница между версиями" });

    expect(onApplyResult).toHaveBeenCalledWith(child);

    expect(screen.getByText("Объект дальше от моря")).toBeVisible();
    expect(screen.getByText("Вылет на два дня позже")).toBeVisible();
    expect(screen.getByText("Ослаблено предпочтение: Море")).toBeVisible();
    expect(screen.getByText("Ослаблено предпочтение: Даты")).toBeVisible();
    expect(document.querySelectorAll(".delta-item")).toHaveLength(2);

    const itemAmounts = Array.from(document.querySelectorAll(".delta-item__amount"))
      .map((node) => node.textContent);
    const displayedSum = document.querySelector(".delta-sum__value")?.textContent;
    const displayedChange = document.querySelector(".delta-total__change")?.textContent;

    expect(itemAmounts).toHaveLength(2);
    expect(displayedSum).toBe(displayedChange);
    expect(document.querySelector(".delta-sum")).not.toHaveClass("delta-sum--broken");
    expect(screen.getByText(/Сходится с общим изменением/)).toBeVisible();

    expect(screen.getByText(/153\s*000\s*₽/)).toBeVisible();
    expect(screen.getByText(/142\s*600\s*₽/)).toBeVisible();
    expect(screen.getAllByText(/−10\s*400\s*₽/).length).toBeGreaterThanOrEqual(2);
  });

  it("shows the match move, which dimensions changed, and the risks that appeared or resolved", async () => {
    const user = userEvent.setup();
    renderPanel(vi.fn().mockResolvedValue(job()));

    moveSlider("Дешевле ↔ комфортнее", -1);
    await user.click(screen.getByRole("button", { name: "Пересчитать будущее" }));
    await screen.findByRole("heading", { name: "Разница между версиями" });

    expect(screen.getByText("88%")).toBeVisible();
    expect(screen.getByText("86%")).toBeVisible();
    expect(screen.getByText("−2 п.п.")).toBeVisible();

    const worsened = document.querySelector(".delta-dimension--worsened");
    expect(worsened).toHaveTextContent("Море");
    expect(worsened).toHaveTextContent("стало хуже");
    expect(document.querySelector(".delta-dimension--improved")).toHaveTextContent("Общий бюджет");
    expect(document.querySelector(".delta-dimension--unchanged")).toHaveTextContent("Тишина");

    const newRisks = document.querySelector(".delta-risk-list--new");
    expect(newRisks).toHaveTextContent("Ночной шум");
    expect(newRisks).toHaveTextContent("риск высокий");
    expect(document.querySelector(".delta-risk-list--resolved")).toHaveTextContent("Толпы людей");

    // The room rate is modeled and the fare is observed; a delta mixing them has to say so.
    expect(screen.getByText(/наблюдаемые: Перелёт/)).toBeVisible();
    expect(screen.getByText(/моделируемые: Проживание/)).toBeVisible();
    expect(screen.getByText(/смешивает наблюдаемые и моделируемые/)).toBeVisible();
  });

  it("surfaces delta arithmetic that does not add up instead of hiding it", async () => {
    const user = userEvent.setup();
    const broken: Job = job({
      result: {
        kind: "future",
        future: {
          ...child,
          delta: {
            ...delta,
            items: [delta.items[0]],
          },
        },
      },
    });
    renderPanel(vi.fn().mockResolvedValue(broken));

    moveSlider("Дешевле ↔ комфортнее", -1);
    await user.click(screen.getByRole("button", { name: "Пересчитать будущее" }));
    await screen.findByRole("heading", { name: "Разница между версиями" });

    const complaint = await screen.findByRole("alert");
    expect(complaint).toHaveTextContent(/Арифметика не сходится/);
    expect(complaint).toHaveTextContent(/расхождение/);
    expect(document.querySelector(".delta-sum")).toHaveClass("delta-sum--broken");
  });

  it("renders the no_solution reason and alternatives rather than a success state", async () => {
    const user = userEvent.setup();
    const onSimulate = vi.fn().mockResolvedValue(job({
      result: {
        kind: "no_solution",
        no_solution: {
          reason: "Дешевле этого уровня не выходит без отказа от моря или тишины.",
          unsatisfiable_constraints: ["total_budget", "sea_access"],
          nearest_alternatives: [parent],
        },
      },
    }));
    const { onApplyResult } = renderPanel(onSimulate);

    await user.type(screen.getByLabelText("Скажите словами"), "Сделай дешевле в два раза");
    await user.click(screen.getByRole("button", { name: "Применить инструкцию" }));

    await screen.findByRole("heading", { name: "Запрос выполнить нельзя" });

    expect(screen.getByText("Дешевле этого уровня не выходит без отказа от моря или тишины.")).toBeVisible();
    expect(screen.getByText("Общий бюджет")).toBeVisible();
    expect(screen.getByText("Море")).toBeVisible();
    expect(screen.getByText(/Это не то, о чём вы просили/)).toBeVisible();

    const alternative = document.querySelector(".alternative-card");
    expect(alternative).not.toBeNull();
    expect(within(alternative as HTMLElement).getByRole("heading", { name: "Сочи" })).toBeVisible();
    expect(within(alternative as HTMLElement).getByText(/153\s*000\s*₽/)).toBeVisible();
    expect(within(alternative as HTMLElement).getByText(/Match 88%/)).toBeVisible();

    // No success state: no delta, and the parent is not asked to store a new version.
    expect(screen.queryByRole("heading", { name: "Разница между версиями" })).not.toBeInTheDocument();
    expect(onApplyResult).not.toHaveBeenCalled();
  });

  it("is busy without claiming progress, then reports a failed job", async () => {
    const user = userEvent.setup();
    let settle: ((value: Job) => void) | undefined;
    const onSimulate = vi.fn().mockImplementation(() => new Promise<Job>((resolve) => { settle = resolve; }));
    renderPanel(onSimulate);

    moveSlider("Дешевле ↔ комфортнее", -1);
    await user.click(screen.getByRole("button", { name: "Пересчитать будущее" }));

    const panel = screen.getByRole("region", { name: /Измените будущее/ });
    expect(panel).toHaveAttribute("aria-busy", "true");
    expect(screen.getByRole("status")).toHaveTextContent(/промежуточного прогресса у неё нет/);
    expect(screen.getByRole("button", { name: "Пересчитываем…" })).toBeDisabled();

    settle?.(job({
      status: "failed",
      result: null,
      error: { title: "Симуляция упала", detail: "Провайдер не ответил при перерасчёте перелёта." },
    }));

    const failure = await screen.findByRole("alert");
    expect(failure).toHaveTextContent("Провайдер не ответил при перерасчёте перелёта.");
    await waitFor(() => expect(panel).toHaveAttribute("aria-busy", "false"));
    expect(screen.queryByRole("heading", { name: "Разница между версиями" })).not.toBeInTheDocument();
  });

  it("does not treat a job without a result as a success", async () => {
    const user = userEvent.setup();
    renderPanel(vi.fn().mockResolvedValue(job({ result: null })));

    moveSlider("Дешевле ↔ комфортнее", -1);
    await user.click(screen.getByRole("button", { name: "Пересчитать будущее" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(/результата в ней нет/);
  });
});
