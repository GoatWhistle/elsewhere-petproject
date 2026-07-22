import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { App } from "./App";
import { ApiProblem } from "./generated/client";
import type { PlanningSession } from "./generated/client";

const api = vi.hoisted(() => ({
  createSession: vi.fn(),
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
    expect(screen.getByText("quiet · inferred")).toBeVisible();
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
