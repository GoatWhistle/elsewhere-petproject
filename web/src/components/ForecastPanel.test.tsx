import { act, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import type { Forecast } from "../generated/client";
import { ForecastPanel } from "./ForecastPanel";

const FUTURE_ID = "6b5a1dd0-12d9-4bbf-8dc5-4d1bdfd52a01";

const forecast: Forecast = {
  future_id: FUTURE_ID,
  generated_at: "2026-08-28T09:10:00Z",
  risks: [
    {
      id: `${FUTURE_ID}-night-noise`,
      risk_type: "night_noise",
      severity: "high",
      confidence: 0.5,
      claim_kind: "model_inference",
      affected_dimension: "quiet",
      statement: "Дорога класса primary проходит в 180 м — ближе 300 м, с которых шум обычно слышен.",
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
          id: `${FUTURE_ID}-quiet-room`,
          description: "Объект на квартал дальше от дороги",
          price_change: { amount_minor: 340_000, currency: "RUB" },
          severity_after: "low",
        },
      ],
    },
    {
      id: `${FUTURE_ID}-weather`,
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

const noop = async () => {};

describe("ForecastPanel", () => {
  it("marks a model inference as an inference and never as a noise measurement", () => {
    render(<ForecastPanel forecast={forecast} isLoading={false} error={null} onFixRisk={noop} />);

    const noise = screen.getByRole("heading", { name: "Ночной шум" }).closest("article");
    expect(noise).not.toBeNull();
    const card = within(noise as HTMLElement);

    expect(card.getByText("предположение модели")).toBeVisible();
    expect(card.getByText(/Это вывод, а не измерение/)).toBeVisible();
    expect(card.getByText(/Шум никто не измерял/)).toBeVisible();
    expect(noise).toHaveClass("risk-card--inference");

    // Evidence with its source and recency, not a bare claim.
    expect(card.getByText("гео-измерение")).toBeVisible();
    expect(card.getByText(/Ближайшая крупная дорога: 180 м/)).toBeVisible();
    expect(card.getByText(/наблюдение от 20 авг\. 2026/)).toBeVisible();

    // Severity and confidence are read as two separate axes.
    expect(card.getByText("Серьёзность").parentElement).toHaveTextContent("высокая");
    expect(card.getByText("Уверенность").parentElement).toHaveTextContent("50%");
    expect(card.getByText(/Задевает предпочтение:/)).toHaveTextContent("Тишина");
  });

  it("keeps a derived metric visually distinct from an inference", () => {
    render(<ForecastPanel forecast={forecast} isLoading={false} error={null} onFixRisk={noop} />);

    const weather = screen.getByRole("heading", { name: "Погода не та" }).closest("article");
    expect(weather).not.toBeNull();
    expect(weather).not.toHaveClass("risk-card--inference");
    expect(within(weather as HTMLElement).getByText("расчёт по данным")).toBeVisible();
    expect(within(weather as HTMLElement).queryByText(/Шум никто не измерял/)).not.toBeInTheDocument();
  });

  it("renders every unassessed risk type with its reason as a block of its own", () => {
    render(<ForecastPanel forecast={forecast} isLoading={false} error={null} onFixRisk={noop} />);

    expect(screen.getByText(/Оценено/)).toHaveTextContent("Оценено 4 из 9 типов рисков");

    const coverage = screen.getByRole("region", { name: "Чего мы не проверяли" });
    const gaps = within(coverage);
    expect(gaps.getByText(/5 из 9 типов рисков не оценены вообще/)).toBeVisible();
    for (const label of ["Толпы людей", "Стройка рядом", "Слабый транспорт", "Номер или расположение не те", "Сезонные закрытия"]) {
      expect(gaps.getByText(label)).toBeVisible();
    }
    expect(gaps.getAllByText("Нужны отзывы: источника с текстом отзывов нет")).toHaveLength(5);
  });

  it("counts a risk type the server never mentioned as unchecked", () => {
    const partial: Forecast = {
      ...forecast,
      coverage: [{ risk_type: "night_noise", assessed: true }],
    };
    render(<ForecastPanel forecast={partial} isLoading={false} error={null} onFixRisk={noop} />);

    expect(screen.getByText(/Оценено/)).toHaveTextContent("Оценено 1 из 9 типов рисков");
    const coverage = within(screen.getByRole("region", { name: "Чего мы не проверяли" }));
    expect(coverage.getAllByText("Причина не указана — считаем тип непроверенным.")).toHaveLength(8);
  });

  it("shows the price change and the resulting severity before the fix is committed", async () => {
    const user = userEvent.setup();
    const onFixRisk = vi.fn().mockResolvedValue(undefined);
    render(<ForecastPanel forecast={forecast} isLoading={false} error={null} onFixRisk={onFixRisk} />);

    const button = screen.getByRole("button", { name: "Устранить риск" });
    const mitigation = button.parentElement as HTMLElement;

    expect(within(mitigation).getByText(/\+3\s*400\s*₽/)).toBeVisible();
    expect(within(mitigation).getByText("серьёзность высокая → низкая")).toBeVisible();
    expect(onFixRisk).not.toHaveBeenCalled();

    await user.click(button);

    expect(onFixRisk).toHaveBeenCalledTimes(1);
    expect(onFixRisk).toHaveBeenCalledWith(`${FUTURE_ID}-night-noise`, `${FUTURE_ID}-quiet-room`);
  });

  it("marks the risk busy while the mitigation is being applied and reports a failure", async () => {
    const user = userEvent.setup();
    let reject: (reason: Error) => void = () => {};
    const pending = new Promise<void>((_resolve, rejectPending) => { reject = rejectPending; });
    const onFixRisk = vi.fn().mockReturnValue(pending);
    render(<ForecastPanel forecast={forecast} isLoading={false} error={null} onFixRisk={onFixRisk} />);

    const noise = screen.getByRole("heading", { name: "Ночной шум" }).closest("article") as HTMLElement;
    await user.click(within(noise).getByRole("button", { name: "Устранить риск" }));

    expect(noise).toHaveAttribute("aria-busy", "true");
    expect(within(noise).getByRole("button", { name: "Пересчитываем будущее…" })).toBeDisabled();

    await act(async () => { reject(new Error("boom")); });

    expect(within(noise).getByRole("alert")).toHaveTextContent("Будущее осталось прежним");
    expect(noise).not.toHaveAttribute("aria-busy");
  });

  it("separates a forecast that found nothing from one that could not run", () => {
    const { unmount } = render(
      <ForecastPanel forecast={{ ...forecast, risks: [] }} isLoading={false} error={null} onFixRisk={noop} />,
    );

    expect(screen.getByText(/ни один не превысил порог/)).toBeVisible();
    expect(screen.getByText(/непроверенными остались 5 из 9 типов/)).toBeVisible();
    expect(screen.queryByRole("alert")).not.toBeInTheDocument();
    unmount();

    render(<ForecastPanel forecast={null} isLoading={false} error="Сервис прогноза не ответил" onFixRisk={noop} />);

    const failure = screen.getByRole("alert");
    expect(within(failure).getByRole("heading", { name: "Прогноз не построен" })).toBeVisible();
    expect(within(failure).getByText("Сервис прогноза не ответил")).toBeVisible();
    expect(within(failure).getByText(/Это не значит, что рисков нет/)).toBeVisible();
    expect(screen.queryByText(/ни один не превысил порог/)).not.toBeInTheDocument();
  });

  it("announces loading with a status role and marks the panel busy", () => {
    render(<ForecastPanel forecast={null} isLoading error={null} onFixRisk={noop} />);

    expect(screen.getByRole("status")).toHaveTextContent("Проверяем риски");
    expect(screen.getByRole("region", { name: "Что может пойти не так именно у вас" }))
      .toHaveAttribute("aria-busy", "true");
  });

  it("says when evidence has no observation date instead of implying it is fresh", () => {
    const undated: Forecast = {
      ...forecast,
      risks: [{ ...forecast.risks[0], evidence: [{ source: "provider_metadata", excerpt: "Данные объекта" }] }],
    };
    render(<ForecastPanel forecast={undated} isLoading={false} error={null} onFixRisk={noop} />);

    expect(screen.getByText(/дата наблюдения неизвестна/)).toBeVisible();
  });
});
