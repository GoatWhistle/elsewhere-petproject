import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import type { TravelDna } from "../generated/client";
import { TravelDnaPanel } from "./TravelDnaPanel";

const makeDna = (overrides: Partial<TravelDna> = {}): TravelDna => ({
  id: "dna-1",
  version: 1,
  elements: [
    {
      dimension: "dates",
      kind: "hard_constraint",
      target: { earliest: "2026-09-10", latest: "2026-09-24", nights_min: 6, nights_max: 8 },
      weight: null,
      provenance: "stated",
      confidence: 1,
    },
    {
      dimension: "quiet",
      kind: "preference",
      target: "high",
      weight: 0.7,
      provenance: "inferred",
      confidence: 0.6,
    },
    {
      dimension: "trip_length",
      kind: "hard_constraint",
      target: { min: 6, max: 8 },
      weight: null,
      provenance: "stated",
      confidence: 1,
    },
  ],
  unmatched_intent: [],
  ...overrides,
});

const props = (onSave: (elements: Parameters<NonNullable<React.ComponentProps<typeof TravelDnaPanel>["onSave"]>>[0]) => Promise<void>) => ({
  dna: makeDna(),
  isSaving: false,
  error: null,
  onSave,
});

describe("TravelDnaPanel", () => {
  it("edits weight, sends the payload, and rerenders the new DNA version", async () => {
    const user = userEvent.setup();
    const onSave = vi.fn().mockResolvedValue(undefined);
    const { rerender } = render(<TravelDnaPanel {...props(onSave)} />);

    fireEvent.change(screen.getByLabelText("Важность: Тишина"), { target: { value: "0.9" } });
    await user.click(screen.getByRole("button", { name: "Сохранить Travel DNA" }));

    expect(onSave).toHaveBeenCalledWith(expect.arrayContaining([
      expect.objectContaining({ dimension: "quiet", target: "high", weight: 0.9 }),
    ]));

    rerender(<TravelDnaPanel {...props(onSave)} dna={makeDna({
      id: "dna-2",
      version: 2,
      elements: makeDna().elements.map((element) => element.dimension === "quiet"
        ? { ...element, target: "very high", weight: 0.9, provenance: "confirmed", confidence: 1 }
        : element),
    })} />);

    expect(screen.getByText("Версия 2")).toBeVisible();
    expect(screen.getByLabelText("Значение: Тишина")).toHaveValue("very high");
    expect(screen.getByText("Подтверждено вами")).toBeVisible();
  });

  it("keeps targets attached to dimensions when the server changes element order", () => {
    const { rerender } = render(<TravelDnaPanel {...props(vi.fn())} />);
    const reordered = [...makeDna().elements].reverse();

    rerender(<TravelDnaPanel {...props(vi.fn())} dna={makeDna({ elements: reordered })} />);

    expect(screen.getByLabelText("Значение: Тишина")).toHaveValue("high");
    expect(screen.getByLabelText("Дата начала")).toHaveValue("2026-09-10");
    expect(screen.getByLabelText("Минимум ночей")).toHaveValue(6);
  });

  it("renders dates as structured controls and includes their edited shape in the payload", async () => {
    const user = userEvent.setup();
    const onSave = vi.fn().mockResolvedValue(undefined);
    render(<TravelDnaPanel {...props(onSave)} />);

    expect(screen.queryByRole("textbox", { name: "Значение: Даты" })).not.toBeInTheDocument();
    await user.clear(screen.getByLabelText("Дата начала"));
    await user.type(screen.getByLabelText("Дата начала"), "2026-09-12");
    await user.click(screen.getByRole("button", { name: "Сохранить Travel DNA" }));

    expect(onSave).toHaveBeenCalledWith(expect.arrayContaining([
      expect.objectContaining({
        dimension: "dates",
        target: { earliest: "2026-09-12", latest: "2026-09-24", nights_min: 6, nights_max: 8 },
      }),
    ]));
  });

  it("shows a validation error and does not save invalid JSON", async () => {
    const user = userEvent.setup();
    const onSave = vi.fn().mockResolvedValue(undefined);
    render(<TravelDnaPanel {...props(onSave)} />);
    const editor = screen.getByRole("textbox", { name: "Значение: Длительность" });

    await user.clear(editor);
    fireEvent.change(editor, { target: { value: "{invalid" } });
    await user.click(screen.getByRole("button", { name: "Сохранить Travel DNA" }));

    expect(onSave).not.toHaveBeenCalled();
    expect(screen.getByRole("alert")).toHaveTextContent("Длительность");
    expect(editor).toHaveValue("{invalid");
  });

  it("keeps edits and shows an error when saving is rejected", async () => {
    const user = userEvent.setup();
    const onSave = vi.fn().mockRejectedValue(new Error("network"));
    render(<TravelDnaPanel {...props(onSave)} />);

    await user.clear(screen.getByLabelText("Значение: Тишина"));
    await user.type(screen.getByLabelText("Значение: Тишина"), "very quiet");
    await user.click(screen.getByRole("button", { name: "Сохранить Travel DNA" }));

    await waitFor(() => expect(screen.getByRole("alert")).toHaveTextContent("Изменения не сохранены"));
    expect(screen.getByLabelText("Значение: Тишина")).toHaveValue("very quiet");
    expect(screen.getByRole("button", { name: "Сохранить Travel DNA" })).toBeEnabled();
  });
});
