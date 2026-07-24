import { useEffect, useState } from "react";
import type {
  Dimension,
  TravelDna,
  TravelDnaElement,
  TravelDnaElementInput,
} from "../generated/client";

type TravelDnaPanelProps = {
  dna: TravelDna;
  isSaving: boolean;
  error: string | null;
  onSave: (elements: TravelDnaElementInput[]) => Promise<void>;
};

type DraftElements = Record<Dimension, TravelDnaElementInput>;
type TargetDrafts = Record<Dimension, string>;

const EMPTY_DRAFT_ELEMENTS = {} as DraftElements;
const EMPTY_TARGET_DRAFTS = {} as TargetDrafts;

const DIMENSION_LABELS: Record<Dimension, string> = {
  total_budget: "Общий бюджет",
  trip_length: "Длительность",
  dates: "Даты",
  sea_access: "Доступ к морю",
  climate_warm: "Тёплый климат",
  quiet: "Тишина",
  food_quality: "Еда",
  walkability: "Пешая доступность",
  nature_vs_city: "Природа или город",
  crowds: "Толпы людей",
  nightlife: "Ночная жизнь",
  comfort: "Комфорт",
  car_free: "Без машины",
  transfer_simplicity: "Простой трансфер",
};

const KIND_LABELS = {
  hard_constraint: "обязательное условие",
  preference: "предпочтение",
  aversion: "что хочется избежать",
} as const;

export function TravelDnaPanel({ dna, isSaving, error, onSave }: TravelDnaPanelProps) {
  const [draftElements, setDraftElements] = useState<DraftElements>(EMPTY_DRAFT_ELEMENTS);
  const [targetDrafts, setTargetDrafts] = useState<TargetDrafts>(EMPTY_TARGET_DRAFTS);
  const [isEditing, setIsEditing] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  useEffect(() => {
    setDraftElements(Object.fromEntries(dna.elements.map((element) => [element.dimension, toInput(element)])) as DraftElements);
    setTargetDrafts(Object.fromEntries(dna.elements.map((element) => [element.dimension, targetText(element)])) as TargetDrafts);
    setIsEditing(false);
    setSaveError(null);
  }, [dna]);

  const updateTarget = (dimension: Dimension, rawValue: string) => {
    const original = dna.elements.find((element) => element.dimension === dimension);
    if (!original) return;
    setTargetDrafts((current) => ({ ...current, [dimension]: rawValue }));
    setDraftElements((current) => ({
      ...current,
      [dimension]: isStructuredTarget(original.target)
        ? current[dimension]
        : { ...current[dimension], target: parseScalarTarget(original.target, rawValue) },
    }));
    setIsEditing(true);
  };

  const updateWeight = (dimension: Dimension, rawValue: string) => {
    setDraftElements((current) => ({
      ...current,
      [dimension]: { ...current[dimension], weight: Number(rawValue) },
    }));
    setIsEditing(true);
  };

  const handleSave = async () => {
    const elements: TravelDnaElementInput[] = [];

    for (const original of dna.elements) {
      const draft = draftElements[original.dimension];
      if (!draft) continue;
      let target = draft.target;

      if (isStructuredTarget(original.target)) {
        try {
          target = JSON.parse(targetDrafts[original.dimension] ?? "");
        } catch {
          setSaveError(`Проверьте значение «${DIMENSION_LABELS[original.dimension]}»: нужен корректный JSON.`);
          return;
        }
      }

      elements.push({
        dimension: draft.dimension,
        kind: draft.kind,
        target,
        weight: draft.weight ?? null,
      });
    }

    setSaveError(null);
    try {
      await onSave(elements);
      setIsEditing(false);
    } catch {
      setSaveError("Изменения не сохранены. Попробуйте ещё раз.");
    }
  };

  return (
    <section className="dna-panel" aria-labelledby="dna-panel-title">
      <div className="dna-panel__heading">
        <div>
          <span className="result-kicker">02 · Travel DNA</span>
          <h3 id="dna-panel-title">Вот что мы поняли о вас</h3>
        </div>
        <span className="dna-version">Версия {dna.version}</span>
      </div>
      <p className="dna-panel__intro">
        Исправьте любое предположение. После сохранения ваша версия станет подтверждённой и будет использована
        для следующих вариантов.
      </p>

      <div className="dna-elements">
        {dna.elements.map((original) => {
          const element = draftElements[original.dimension];
          if (!element) return null;
          return (
            <article className="dna-element" key={element.dimension}>
              <div className="dna-element__topline">
                <div>
                  <h4>{DIMENSION_LABELS[element.dimension]}</h4>
                  <span className="dna-kind">{KIND_LABELS[element.kind]}</span>
                </div>
                <span className={`provenance provenance--${original.provenance}`}>
                  {provenanceLabel(original.provenance)}
                </span>
              </div>

              <label className="dna-control">
                <span>Что для вас верно</span>
                <TargetEditor
                  element={original}
                  value={targetDrafts[element.dimension] ?? ""}
                  disabled={isSaving}
                  onChange={(value) => updateTarget(element.dimension, value)}
                />
              </label>

              {element.weight !== null && element.weight !== undefined && (
                <label className="dna-control dna-weight">
                  <span>
                    Важность <strong>{Math.round((element.weight ?? 0) * 100)}%</strong>
                  </span>
                  <input
                    aria-label={`Важность: ${DIMENSION_LABELS[element.dimension]}`}
                    type="range"
                    min="0"
                    max="1"
                    step="0.05"
                    value={element.weight}
                    disabled={isSaving}
                    onChange={(event) => updateWeight(element.dimension, event.target.value)}
                  />
                </label>
              )}

              <div className="dna-element__meta">
                <span>Уверенность системы: <strong>{Math.round(original.confidence * 100)}%</strong></span>
                {element.weight === null || element.weight === undefined ? (
                  <span>Вес: не применяется</span>
                ) : (
                  <span>Вес: <strong>{Math.round((element.weight ?? 0) * 100)}%</strong></span>
                )}
              </div>
            </article>
          );
        })}
      </div>

      {dna.unmatched_intent.length > 0 && (
        <div className="unmatched-intent">
          <strong>Пока не удалось учесть</strong>
          <ul>
            {dna.unmatched_intent.map((intent) => <li key={intent}>{intent}</li>)}
          </ul>
        </div>
      )}

      {(error || saveError) && <p className="dna-save-error" role="alert">{saveError || error}</p>}

      <div className="dna-panel__actions">
        {isEditing && <span className="unsaved-note">Есть несохранённые изменения</span>}
        <button
          className="secondary-action"
          type="button"
          disabled={isSaving || !isEditing}
          onClick={handleSave}
        >
          {isSaving ? "Сохраняем вашу версию…" : "Сохранить Travel DNA"}
        </button>
      </div>
    </section>
  );
}

function TargetEditor({
  element,
  value,
  disabled,
  onChange,
}: {
  element: TravelDnaElement;
  value: string;
  disabled: boolean;
  onChange: (value: string) => void;
}) {
  if (typeof element.target === "boolean") {
    return (
      <select aria-label={`Значение: ${DIMENSION_LABELS[element.dimension]}`} value={value} disabled={disabled} onChange={(event) => onChange(event.target.value)}>
        <option value="true">Да</option>
        <option value="false">Нет</option>
      </select>
    );
  }

  if (typeof element.target === "number") {
    return (
      <input
        aria-label={`Значение: ${DIMENSION_LABELS[element.dimension]}`}
        type="number"
        min="0"
        max="1"
        step="0.05"
        value={value}
        disabled={disabled}
        onChange={(event) => onChange(event.target.value)}
      />
    );
  }

  if (isStructuredTarget(element.target)) {
    if (element.dimension === "dates" && isDateTarget(element.target)) {
      return (
        <DateTargetEditor
          value={value}
          disabled={disabled}
          onChange={onChange}
        />
      );
    }
    return (
      <textarea
        aria-label={`Значение: ${DIMENSION_LABELS[element.dimension]}`}
        rows={3}
        value={value}
        disabled={disabled}
        onChange={(event) => onChange(event.target.value)}
      />
    );
  }

  return (
    <input
      aria-label={`Значение: ${DIMENSION_LABELS[element.dimension]}`}
      type="text"
      value={value}
      disabled={disabled}
      onChange={(event) => onChange(event.target.value)}
    />
  );
}

type DateTarget = {
  earliest: string;
  latest: string;
  nights_min: number;
  nights_max: number;
};

function DateTargetEditor({
  value,
  disabled,
  onChange,
}: {
  value: string;
  disabled: boolean;
  onChange: (value: string) => void;
}) {
  const target = JSON.parse(value) as DateTarget;
  const update = (field: keyof DateTarget, rawValue: string) => {
    const next = { ...target, [field]: field.startsWith("nights_") ? Number(rawValue) : rawValue };
    onChange(JSON.stringify(next));
  };

  return (
    <div className="dna-date-editor">
      <label>С
        <input aria-label="Дата начала" type="date" value={target.earliest} disabled={disabled} onChange={(event) => update("earliest", event.target.value)} />
      </label>
      <label>По
        <input aria-label="Дата окончания" type="date" value={target.latest} disabled={disabled} onChange={(event) => update("latest", event.target.value)} />
      </label>
      <label>Ночей от
        <input aria-label="Минимум ночей" type="number" min="1" value={target.nights_min} disabled={disabled} onChange={(event) => update("nights_min", event.target.value)} />
      </label>
      <label>Ночей до
        <input aria-label="Максимум ночей" type="number" min="1" value={target.nights_max} disabled={disabled} onChange={(event) => update("nights_max", event.target.value)} />
      </label>
    </div>
  );
}

function toInput(element: TravelDnaElement): TravelDnaElementInput {
  return {
    dimension: element.dimension,
    kind: element.kind,
    target: element.target,
    weight: element.weight ?? null,
  };
}

function targetText(element: TravelDnaElement) {
  return isStructuredTarget(element.target) ? JSON.stringify(element.target, null, 2) : String(element.target ?? "");
}

function isStructuredTarget(target: unknown): target is Record<string, unknown> | unknown[] {
  return typeof target === "object" && target !== null;
}

function isDateTarget(target: unknown): target is DateTarget {
  if (!isStructuredTarget(target) || Array.isArray(target)) return false;
  return typeof target.earliest === "string"
    && typeof target.latest === "string"
    && typeof target.nights_min === "number"
    && typeof target.nights_max === "number";
}

function parseScalarTarget(original: unknown, value: string) {
  if (typeof original === "boolean") return value === "true";
  if (typeof original === "number") return Number(value);
  return value;
}

function provenanceLabel(provenance: TravelDnaElement["provenance"]) {
  return {
    stated: "Вы сказали",
    inferred: "Предположение",
    confirmed: "Подтверждено вами",
    default: "По умолчанию",
  }[provenance];
}
