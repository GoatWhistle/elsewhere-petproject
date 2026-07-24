import { fireEvent, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { App } from "./App";
import { ApiProblem } from "./generated/client";
import type { PlanningSession } from "./generated/client";

const api = vi.hoisted(() => ({
  createSession: vi.fn(),
  updateTravelDna: vi.fn(),
  generateFutures: vi.fn(),
}));

vi.mock("./api", () => api);

const session: PlanningSession = {
  id: "03571d18-8537-48aa-995c-fc0f9a41ba51",
  created_at: "2026-08-28T09:00:00Z",
  dream_text: "Тихо у моря",
  travel_dna: {
    id: "a3fe8185-7565-4f9f-84c7-b12d7c7c62d8",
    version: 1,
    elements: [
      {
        dimension: "quiet",
        kind: "preference",
        target: "high",
        weight: 0.7,
        tolerance: 0.2,
        provenance: "inferred",
        confidence: 0.6,
      },
    ],
    unmatched_intent: [],
  },
  clarifications: [],
};

beforeEach(() => {
  api.createSession.mockReset();
  api.updateTravelDna.mockReset();
  api.generateFutures.mockReset();
});

describe("App Dream journey", () => {
  it("creates a session and confirms every submitted structured field", async () => {
    const user = userEvent.setup();
    api.createSession.mockResolvedValue(session);
    render(<App />);

    await fillDream(user);
    await user.click(screen.getByRole("button", { name: "Собрать Travel DNA" }));

    expect(await screen.findByRole("heading", { name: "Вот что мы услышали" })).toBeVisible();
    expect(screen.getByText("MOW")).toBeVisible();
    expect(screen.getByText("10 сент. 2026 г. — 24 сент. 2026 г.")).toBeVisible();
    expect(screen.getByText("6–8 ночей")).toBeVisible();
    expect(screen.getByLabelText("Значение: Тишина")).toHaveValue("high");
    expect(screen.getByText("Уверенность системы:").parentElement).toHaveTextContent("60%");
  });

  it("saves a correction as a new confirmed DNA version", async () => {
    const user = userEvent.setup();
    api.createSession.mockResolvedValue(session);
    api.updateTravelDna.mockResolvedValue({
      ...session.travel_dna,
      id: "b4ef9296-8666-4f9f-95d8-c8e8e8d8e8d8",
      version: 2,
      elements: [{
        ...session.travel_dna.elements[0],
        target: "very high",
        weight: 0.9,
        provenance: "confirmed",
        confidence: 1,
      }],
    });
    render(<App />);

    await fillDream(user);
    await user.click(screen.getByRole("button", { name: "Собрать Travel DNA" }));
    await user.clear(screen.getByLabelText("Значение: Тишина"));
    await user.type(screen.getByLabelText("Значение: Тишина"), "very high");
    fireEvent.change(screen.getByLabelText("Важность: Тишина"), { target: { value: "0.9" } });
    await user.click(screen.getByRole("button", { name: "Сохранить Travel DNA" }));

    expect(api.updateTravelDna).toHaveBeenCalledOnce();
    expect(api.updateTravelDna).toHaveBeenCalledWith(session.id, [{
      dimension: "quiet",
      kind: "preference",
      target: "very high",
      weight: 0.9,
    }]);
    expect(await screen.findByText("Версия 2")).toBeVisible();
    expect(screen.getByText("Подтверждено вами")).toBeVisible();
  });

  it("shows the detail from an API problem", async () => {
    const user = userEvent.setup();
    api.createSession.mockRejectedValue(new ApiProblem(422, {
      title: "Некорректные данные",
      status: 422,
      detail: "Город вылета неизвестен.",
    }));
    render(<App />);

    await fillDream(user);
    await user.click(screen.getByRole("button", { name: "Собрать Travel DNA" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Город вылета неизвестен.");
  });
});

async function fillDream(user: ReturnType<typeof userEvent.setup>) {
  await user.type(screen.getByLabelText("Какой должна быть эта поездка?"), "Тихо у моря");
  await user.type(screen.getByLabelText("Откуда"), "MOW");
  await user.type(screen.getByLabelText("Можно уехать с"), "2026-09-10");
  await user.type(screen.getByLabelText("Вернуться не позже"), "2026-09-24");
  await user.type(screen.getByLabelText("Ночей, минимум"), "6");
  await user.type(screen.getByLabelText("Ночей, максимум"), "8");
  await user.selectOptions(screen.getByLabelText("Взрослых"), "2");
}
