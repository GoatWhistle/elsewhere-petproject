import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { DreamForm } from "./DreamForm";

describe("DreamForm", () => {
  it("locks the inputs while the request is in flight", () => {
    render(<DreamForm isSubmitting onSubmit={vi.fn(async () => undefined)} />);

    expect(screen.getByLabelText("Какой должна быть эта поездка?")).toBeDisabled();
    expect(screen.getByLabelText("Откуда")).toBeDisabled();
    expect(screen.getByRole("button", { name: "Разбираем вашу мечту…" })).toBeDisabled();
  });

  it("requires every field the API contract needs", async () => {
    const onSubmit = vi.fn(async () => undefined);
    render(<DreamForm isSubmitting={false} onSubmit={onSubmit} />);

    await userEvent.click(screen.getByRole("button", { name: "Собрать Travel DNA" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("Проверьте данные поездки");
    expect(screen.getByLabelText("Какой должна быть эта поездка?")).toHaveAttribute("aria-invalid", "true");
    expect(screen.getByLabelText("Откуда")).toHaveAttribute("aria-invalid", "true");
    expect(screen.getByLabelText("Можно уехать с")).toHaveAttribute("aria-invalid", "true");
    expect(screen.getByLabelText("Вернуться не позже")).toHaveAttribute("aria-invalid", "true");
    expect(screen.getByLabelText("Ночей, минимум")).toHaveAttribute("aria-invalid", "true");
    expect(screen.getByLabelText("Ночей, максимум")).toHaveAttribute("aria-invalid", "true");
    expect(screen.getByLabelText("Взрослых")).toHaveAttribute("aria-invalid", "true");
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it("submits the exact DreamInput without invented defaults", async () => {
    const user = userEvent.setup();
    const onSubmit = vi.fn(async () => undefined);
    render(<DreamForm isSubmitting={false} onSubmit={onSubmit} />);

    await user.type(screen.getByLabelText("Какой должна быть эта поездка?"), "  Тихо у моря, вкусно и без машины  ");
    await user.type(screen.getByLabelText("Откуда"), "mow");
    await user.type(screen.getByLabelText("Можно уехать с"), "2026-09-10");
    await user.type(screen.getByLabelText("Вернуться не позже"), "2026-09-24");
    await user.type(screen.getByLabelText("Ночей, минимум"), "6");
    await user.type(screen.getByLabelText("Ночей, максимум"), "8");
    await user.selectOptions(screen.getByLabelText("Взрослых"), "2");
    await user.click(screen.getByRole("button", { name: "Собрать Travel DNA" }));

    expect(onSubmit).toHaveBeenCalledOnce();
    expect(onSubmit).toHaveBeenCalledWith({
      dream_text: "Тихо у моря, вкусно и без машины",
      origin: "MOW",
      date_window: {
        earliest: "2026-09-10",
        latest: "2026-09-24",
        nights_min: 6,
        nights_max: 8,
      },
      party: { adults: 2 },
    });
  });

  it("rejects an inverted date window and duration range", async () => {
    const user = userEvent.setup();
    const onSubmit = vi.fn(async () => undefined);
    render(<DreamForm isSubmitting={false} onSubmit={onSubmit} />);

    await user.type(screen.getByLabelText("Какой должна быть эта поездка?"), "Хочу отдохнуть");
    await user.type(screen.getByLabelText("Откуда"), "LED");
    await user.type(screen.getByLabelText("Можно уехать с"), "2026-10-20");
    await user.type(screen.getByLabelText("Вернуться не позже"), "2026-10-10");
    await user.type(screen.getByLabelText("Ночей, минимум"), "10");
    await user.type(screen.getByLabelText("Ночей, максимум"), "5");
    await user.selectOptions(screen.getByLabelText("Взрослых"), "1");
    await user.click(screen.getByRole("button", { name: "Собрать Travel DNA" }));

    expect(screen.getByText("Дата возвращения должна быть не раньше даты выезда.")).toBeVisible();
    expect(screen.getByText("Максимум не может быть меньше минимума.")).toBeVisible();
    expect(onSubmit).not.toHaveBeenCalled();
  });
});
