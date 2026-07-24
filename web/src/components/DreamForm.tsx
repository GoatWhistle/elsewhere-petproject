import { FormEvent, useRef, useState } from "react";
import type { DreamInput } from "../generated/client";

export type DreamFormValues = {
  dreamText: string;
  origin: string;
  earliest: string;
  latest: string;
  nightsMin: string;
  nightsMax: string;
  adults: string;
};

type FieldName = keyof DreamFormValues;
type FormErrors = Partial<Record<FieldName, string>>;

type DreamFormProps = {
  isSubmitting: boolean;
  onSubmit: (input: DreamInput) => Promise<void>;
};

const initialValues: DreamFormValues = {
  dreamText: "",
  origin: "",
  earliest: "",
  latest: "",
  nightsMin: "",
  nightsMax: "",
  adults: "",
};

export function DreamForm({ isSubmitting, onSubmit }: DreamFormProps) {
  const [values, setValues] = useState(initialValues);
  const [wasSubmitted, setWasSubmitted] = useState(false);
  const errorSummaryRef = useRef<HTMLDivElement>(null);
  const errors = wasSubmitted ? validateDreamForm(values) : {};
  const characterCount = values.dreamText.length;

  const update = (field: FieldName, value: string) => {
    setValues((current) => ({ ...current, [field]: value }));
  };

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const nextErrors = validateDreamForm(values);
    setWasSubmitted(true);

    if (Object.keys(nextErrors).length > 0) {
      requestAnimationFrame(() => errorSummaryRef.current?.focus());
      return;
    }

    await onSubmit(toDreamInput(values));
  };

  return (
    <form className="dream-form" noValidate aria-busy={isSubmitting} onSubmit={handleSubmit}>
      {Object.keys(errors).length > 0 && (
        <div className="error-summary" ref={errorSummaryRef} role="alert" tabIndex={-1}>
          <strong>Проверьте данные поездки</strong>
          <span>Мы отметили поля, без которых нельзя честно рассчитать маршрут и стоимость.</span>
        </div>
      )}

      <div className="dream-field dream-field--wide">
        <div className="field-heading">
          <label htmlFor="dream-text">Какой должна быть эта поездка?</label>
          <span aria-live="polite">{characterCount.toLocaleString("ru-RU")} / 4 000</span>
        </div>
        <textarea
          id="dream-text"
          name="dream_text"
          value={values.dreamText}
          disabled={isSubmitting}
          maxLength={4000}
          rows={6}
          aria-describedby={`dream-text-hint${errors.dreamText ? " dream-text-error" : ""}`}
          aria-invalid={Boolean(errors.dreamText)}
          placeholder="Например: устали, хотим вдвоём на неделю к тёплому морю — спокойно, вкусно и без машины. До 180 000 ₽."
          onChange={(event) => update("dreamText", event.target.value)}
        />
        <p className="field-hint" id="dream-text-hint">
          Пишите своими словами. Бюджет, настроение и важные «нет» полезнее списка фильтров.
        </p>
        <FieldError id="dream-text-error" message={errors.dreamText} />
      </div>

      <fieldset className="trip-essentials" disabled={isSubmitting}>
        <legend>Что нужно знать до поиска</legend>
        <p className="fieldset-intro">
          Эти поля не угадываем: без них нельзя получить реальную цену перелёта.
        </p>

        <div className="form-grid">
          <div className="dream-field dream-field--origin">
            <label htmlFor="origin">Откуда</label>
            <input
              id="origin"
              name="origin"
              value={values.origin}
              type="text"
              inputMode="text"
              autoCapitalize="characters"
              autoComplete="off"
              maxLength={3}
              spellCheck={false}
              aria-describedby={`origin-hint${errors.origin ? " origin-error" : ""}`}
              aria-invalid={Boolean(errors.origin)}
              placeholder="MOW"
              onChange={(event) =>
                update("origin", event.target.value.replace(/[^a-z]/gi, "").toUpperCase().slice(0, 3))
              }
            />
            <p className="field-hint" id="origin-hint">IATA-код города, например MOW.</p>
            <FieldError id="origin-error" message={errors.origin} />
          </div>

          <div className="dream-field">
            <label htmlFor="earliest">Можно уехать с</label>
            <input
              id="earliest"
              name="earliest"
              value={values.earliest}
              type="date"
              aria-describedby={errors.earliest ? "earliest-error" : undefined}
              aria-invalid={Boolean(errors.earliest)}
              onChange={(event) => update("earliest", event.target.value)}
            />
            <FieldError id="earliest-error" message={errors.earliest} />
          </div>

          <div className="dream-field">
            <label htmlFor="latest">Вернуться не позже</label>
            <input
              id="latest"
              name="latest"
              value={values.latest}
              type="date"
              min={values.earliest || undefined}
              aria-describedby={errors.latest ? "latest-error" : undefined}
              aria-invalid={Boolean(errors.latest)}
              onChange={(event) => update("latest", event.target.value)}
            />
            <FieldError id="latest-error" message={errors.latest} />
          </div>

          <div className="dream-field">
            <label htmlFor="nights-min">Ночей, минимум</label>
            <input
              id="nights-min"
              name="nights_min"
              value={values.nightsMin}
              type="number"
              inputMode="numeric"
              min={1}
              step={1}
              aria-describedby={errors.nightsMin ? "nights-min-error" : undefined}
              aria-invalid={Boolean(errors.nightsMin)}
              placeholder="6"
              onChange={(event) => update("nightsMin", event.target.value)}
            />
            <FieldError id="nights-min-error" message={errors.nightsMin} />
          </div>

          <div className="dream-field">
            <label htmlFor="nights-max">Ночей, максимум</label>
            <input
              id="nights-max"
              name="nights_max"
              value={values.nightsMax}
              type="number"
              inputMode="numeric"
              min={1}
              step={1}
              aria-describedby={errors.nightsMax ? "nights-max-error" : undefined}
              aria-invalid={Boolean(errors.nightsMax)}
              placeholder="7"
              onChange={(event) => update("nightsMax", event.target.value)}
            />
            <FieldError id="nights-max-error" message={errors.nightsMax} />
          </div>

          <div className="dream-field">
            <label htmlFor="adults">Взрослых</label>
            <select
              id="adults"
              name="adults"
              value={values.adults}
              aria-describedby={errors.adults ? "adults-error" : undefined}
              aria-invalid={Boolean(errors.adults)}
              onChange={(event) => update("adults", event.target.value)}
            >
              <option value="">Выберите</option>
              <option value="1">1 взрослый</option>
              <option value="2">2 взрослых</option>
            </select>
            <FieldError id="adults-error" message={errors.adults} />
          </div>
        </div>
      </fieldset>

      <div className="form-actions">
        <button className="primary-action" type="submit" disabled={isSubmitting}>
          {isSubmitting ? "Разбираем вашу мечту…" : "Собрать Travel DNA"}
        </button>
        <p>Сначала покажем, что поняли. Вы сможете всё исправить до поиска вариантов.</p>
      </div>
    </form>
  );
}

export function validateDreamForm(values: DreamFormValues): FormErrors {
  const errors: FormErrors = {};
  const dream = values.dreamText.trim();
  const nightsMin = Number(values.nightsMin);
  const nightsMax = Number(values.nightsMax);

  if (!dream) errors.dreamText = "Опишите поездку своими словами.";
  if (dream.length > 4000) errors.dreamText = "Описание должно быть короче 4 000 символов.";
  if (!/^[A-Z]{3}$/.test(values.origin)) errors.origin = "Введите трёхбуквенный IATA-код.";
  if (!values.earliest) errors.earliest = "Укажите начало окна поездки.";
  if (!values.latest) errors.latest = "Укажите конец окна поездки.";
  if (values.earliest && values.latest && values.latest < values.earliest) {
    errors.latest = "Дата возвращения должна быть не раньше даты выезда.";
  }
  if (!Number.isInteger(nightsMin) || nightsMin < 1) {
    errors.nightsMin = "Минимум ночей должен быть целым числом от 1.";
  }
  if (!Number.isInteger(nightsMax) || nightsMax < 1) {
    errors.nightsMax = "Максимум ночей должен быть целым числом от 1.";
  } else if (!errors.nightsMin && nightsMax < nightsMin) {
    errors.nightsMax = "Максимум не может быть меньше минимума.";
  }
  if (values.adults !== "1" && values.adults !== "2") {
    errors.adults = "Для MVP выберите одного или двух взрослых.";
  }

  return errors;
}

export function toDreamInput(values: DreamFormValues): DreamInput {
  return {
    dream_text: values.dreamText.trim(),
    origin: values.origin,
    date_window: {
      earliest: values.earliest,
      latest: values.latest,
      nights_min: Number(values.nightsMin),
      nights_max: Number(values.nightsMax),
    },
    party: { adults: Number(values.adults) as 1 | 2 },
  };
}

function FieldError({ id, message }: { id: string; message?: string }) {
  if (!message) return null;
  return <p className="field-error" id={id}>{message}</p>;
}
