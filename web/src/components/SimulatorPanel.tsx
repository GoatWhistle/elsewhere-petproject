import { useEffect, useId, useState } from "react";
import type {
  Adjustment,
  Delta,
  DeltaItem,
  Dimension,
  Future,
  Job,
  MatchContribution,
  Money,
  NoSolution,
  PriceComponent,
  RiskSummary,
  RiskType,
  SimulationRequest,
} from "../generated/client";
import { ApiProblem } from "../generated/client";
import "./SimulatorPanel.css";

type SimulatorPanelProps = {
  future: Future;
  onSimulate: (request: SimulationRequest) => Promise<Job>;
  onApplyResult: (future: Future) => void;
};

const DIMENSION_LABELS: Record<Dimension, string> = {
  total_budget: "Общий бюджет",
  trip_length: "Длительность",
  dates: "Даты",
  sea_access: "Море",
  climate_warm: "Тёплый климат",
  quiet: "Тишина",
  food_quality: "Еда",
  walkability: "Пешая доступность",
  nature_vs_city: "Природа / город",
  crowds: "Толпы людей",
  nightlife: "Ночная жизнь",
  comfort: "Комфорт",
  car_free: "Без машины",
  transfer_simplicity: "Простой трансфер",
};

const COMPONENT_LABELS: Record<PriceComponent["kind"], string> = {
  travel: "Перелёт",
  accommodation: "Проживание",
  transfer: "Трансфер",
  local_mobility: "Передвижение на месте",
};

const RISK_LABELS: Record<RiskType, string> = {
  night_noise: "Ночной шум",
  crowds: "Толпы людей",
  walkability: "Пешая доступность",
  weather_mismatch: "Погода не та",
  construction: "Стройка рядом",
  transfer_difficulty: "Сложный трансфер",
  weak_transport: "Слабый транспорт",
  room_location_mismatch: "Номер не там, где ждёте",
  seasonal_closure: "Межсезонное закрытие",
};

const SEVERITY_LABELS: Record<RiskSummary["severity"], string> = {
  low: "низкий",
  medium: "средний",
  high: "высокий",
};

const CHANGE_LABELS: Record<Delta["dimension_changes"][number]["change"], string> = {
  improved: "стало лучше",
  worsened: "стало хуже",
  unchanged: "без изменений",
};

const CHANGE_MARKS: Record<Delta["dimension_changes"][number]["change"], string> = {
  improved: "▲",
  worsened: "▼",
  unchanged: "=",
};

const MINOR_UNITS_PER_MAJOR_UNIT = 100;
const MAX_STEPS = 3;

// DEC-025 fixes what each control moves and by how much. A slider that only re-sorts results is a lie,
// so every position here maps to a named dimension, a direction and a magnitude the request carries.
type SliderKey = "cost_comfort" | "quiet_lively" | "city_nature";

type SliderSpec = {
  key: SliderKey;
  label: string;
  leftLabel: string;
  rightLabel: string;
  stepNote: string;
  positionLabel: (steps: number) => string;
  adjustments: (steps: number) => Adjustment[];
};

const SLIDERS: SliderSpec[] = [
  {
    key: "cost_comfort",
    label: "Дешевле ↔ комфортнее",
    leftLabel: "Дешевле",
    rightLabel: "Комфортнее",
    stepNote: "Один шаг — целевая сумма поездки ∓8%",
    positionLabel: (steps) => sidePosition(steps, "дешевле", "комфортнее"),
    adjustments: (steps) => steps === 0 ? [] : [
      { dimension: "total_budget", direction: steps > 0 ? "increase" : "decrease", magnitude: magnitude(0.08, steps) },
    ],
  },
  {
    key: "quiet_lively",
    label: "Тише ↔ живее",
    leftLabel: "Тише",
    rightLabel: "Живее",
    stepNote: "Один шаг — цель по тишине и по ночной жизни на 0,2",
    positionLabel: (steps) => sidePosition(steps, "тише", "живее"),
    adjustments: (steps) => steps === 0 ? [] : [
      { dimension: "quiet", direction: steps > 0 ? "decrease" : "increase", magnitude: magnitude(0.2, steps) },
      { dimension: "nightlife", direction: steps > 0 ? "increase" : "decrease", magnitude: magnitude(0.2, steps) },
    ],
  },
  {
    key: "city_nature",
    label: "Город ↔ природа",
    leftLabel: "Город",
    rightLabel: "Природа",
    stepNote: "Один шаг — цель по оси «природа / город» на 0,2",
    positionLabel: (steps) => sidePosition(steps, "к городу", "к природе"),
    adjustments: (steps) => steps === 0 ? [] : [
      { dimension: "nature_vs_city", direction: steps > 0 ? "increase" : "decrease", magnitude: magnitude(0.2, steps) },
    ],
  },
];

const NEUTRAL: Record<SliderKey, number> = { cost_comfort: 0, quiet_lively: 0, city_nature: 0 };

export function SimulatorPanel({ future, onSimulate, onApplyResult }: SimulatorPanelProps) {
  const [steps, setSteps] = useState<Record<SliderKey, number>>(NEUTRAL);
  const [instruction, setInstruction] = useState("");
  const [persistToTravelDna, setPersistToTravelDna] = useState(false);
  const [isRunning, setIsRunning] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [simulated, setSimulated] = useState<Future | null>(null);
  const [noSolution, setNoSolution] = useState<NoSolution | null>(null);
  const fieldId = useId();

  // A new version is a new starting point: the controls describe a move away from *this* Future, so they
  // go back to neutral whenever the Future under them changes.
  useEffect(() => {
    setSteps(NEUTRAL);
    setInstruction("");
  }, [future.id]);

  const pendingAdjustments = SLIDERS.flatMap((slider) => slider.adjustments(steps[slider.key]));
  const hasPendingAdjustments = pendingAdjustments.length > 0;
  const hasInstruction = instruction.trim().length > 0;
  const currentFuture = simulated ?? future;
  const delta = noSolution ? null : simulated?.delta ?? future.delta ?? null;

  const run = async (request: SimulationRequest) => {
    setIsRunning(true);
    setError(null);
    setNoSolution(null);
    setStatus("Считаем новую версию будущего. Задача выполняется на сервере целиком, промежуточного прогресса у неё нет.");

    try {
      const job = await onSimulate(request);

      if (job.status === "failed") {
        setStatus(null);
        setError(job.error?.detail || job.error?.title || "Расчёт завершился ошибкой без объяснения.");
        return;
      }
      if (job.status !== "succeeded") {
        setStatus(null);
        setError(`Задача вернулась со статусом «${job.status}» и без результата — считать её успешной нельзя.`);
        return;
      }

      const result = job.result;
      if (!result) {
        setStatus(null);
        setError("Задача помечена выполненной, но результата в ней нет.");
        return;
      }

      if (result.kind === "no_solution") {
        if (!result.no_solution) {
          setStatus(null);
          setError("Сервис сообщил, что решения нет, но не сказал почему.");
          return;
        }
        setSimulated(null);
        setNoSolution(result.no_solution);
        setStatus("Запрос выполнить нельзя. Ниже — причина и ближайшие достижимые варианты.");
        return;
      }

      if (result.kind === "future" && result.future) {
        setSimulated(result.future);
        onApplyResult(result.future);
        setStatus(`Готово: версия ${result.future.version}. Предыдущая версия сохранена, она не изменилась.`);
        return;
      }

      setStatus(null);
      setError(`Симуляция вернула результат вида «${result.kind}» — это не новая версия будущего.`);
    } catch (caught) {
      setStatus(null);
      setError(errorMessage(caught));
    } finally {
      setIsRunning(false);
    }
  };

  return (
    <section className="simulator-panel" aria-labelledby="simulator-title" aria-busy={isRunning}>
      <div className="simulator-heading">
        <div>
          <span className="result-kicker">04 · Симуляция</span>
          <h2 id="simulator-title">Измените будущее и посмотрите, чем вы за это заплатили</h2>
        </div>
        <p>
          Каждый сдвиг — это не фильтр, а пересчёт под изменённой целью. Старая версия остаётся: мы создаём
          новую и показываем разницу между ними.
        </p>
      </div>

      <p className="simulator-lineage">
        Сейчас перед вами версия {currentFuture.version}
        {currentFuture.parent_id ? " · получена из предыдущей версии" : " · исходная версия"}
      </p>

      <form
        className="simulator-controls"
        onSubmit={(event) => {
          event.preventDefault();
          if (!hasPendingAdjustments || isRunning) return;
          void run({ adjustments: pendingAdjustments, persist_to_travel_dna: persistToTravelDna });
        }}
      >
        <fieldset disabled={isRunning}>
          <legend>Ползунки</legend>

          {SLIDERS.map((slider) => {
            const value = steps[slider.key];
            const controlId = `${fieldId}-${slider.key}`;
            return (
              <div className="simulator-slider" key={slider.key}>
                <label htmlFor={controlId}>{slider.label}</label>
                <input
                  id={controlId}
                  type="range"
                  min={-MAX_STEPS}
                  max={MAX_STEPS}
                  step={1}
                  value={value}
                  aria-describedby={`${controlId}-note`}
                  aria-valuetext={slider.positionLabel(value)}
                  onChange={(event) => {
                    const next = Number(event.target.value);
                    setSteps((current) => ({ ...current, [slider.key]: next }));
                  }}
                />
                <div className="simulator-slider__ends" aria-hidden="true">
                  <span>{slider.leftLabel}</span>
                  <span>{slider.rightLabel}</span>
                </div>
                <p className="simulator-slider__note" id={`${controlId}-note`}>
                  {slider.stepNote} · сейчас {slider.positionLabel(value)}
                </p>
                {value !== 0 && (
                  <ul className="simulator-slider__adjustments">
                    {slider.adjustments(value).map((adjustment) => (
                      <li key={adjustment.dimension}>
                        {DIMENSION_LABELS[adjustment.dimension]}{" "}
                        {adjustment.direction === "increase" ? "↑" : "↓"} на {formatNumber(adjustment.magnitude ?? 0)}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            );
          })}
        </fieldset>

        <div className="simulator-submit">
          <button className="primary-action" type="submit" disabled={isRunning || !hasPendingAdjustments}>
            {isRunning ? "Пересчитываем…" : "Пересчитать будущее"}
          </button>
          <p className="field-hint">
            {hasPendingAdjustments
              ? `Отправим ${pendingAdjustments.length} ${pluralAdjustments(pendingAdjustments.length)} к модели`
              : "Сдвиньте хотя бы один ползунок — пустой запрос отправлять нечем"}
          </p>
        </div>
      </form>

      <form
        className="simulator-instruction"
        onSubmit={(event) => {
          event.preventDefault();
          if (!hasInstruction || isRunning) return;
          void run({ instruction: instruction.trim(), persist_to_travel_dna: persistToTravelDna });
        }}
      >
        <label htmlFor={`${fieldId}-instruction`}>Скажите словами</label>
        <textarea
          id={`${fieldId}-instruction`}
          value={instruction}
          disabled={isRunning}
          maxLength={1000}
          placeholder="Сделай дешевле, но не испорти важное"
          aria-describedby={`${fieldId}-instruction-note`}
          onChange={(event) => setInstruction(event.target.value)}
        />
        <p className="field-hint" id={`${fieldId}-instruction-note`}>
          Инструкция и ползунки отправляются раздельно: контракт допускает либо одно, либо другое.
        </p>
        <button className="secondary-action" type="submit" disabled={isRunning || !hasInstruction}>
          {isRunning ? "Ждём результат…" : "Применить инструкцию"}
        </button>
      </form>

      <label className="simulator-persist">
        <input
          type="checkbox"
          checked={persistToTravelDna}
          disabled={isRunning}
          onChange={(event) => setPersistToTravelDna(event.target.checked)}
        />
        <span>
          Запомнить это изменение в Travel DNA
          <small>Иначе правка живёт только в этом будущем. Вопрос ещё не закрыт продуктово (OQ-G), поэтому решаете вы.</small>
        </span>
      </label>

      {status && <p className="simulator-status" role="status">{status}</p>}

      {error && (
        <div className="request-error" role="alert">
          <strong>Симуляция не выполнена</strong>
          <span>{error}</span>
        </div>
      )}

      {noSolution && <NoSolutionBlock noSolution={noSolution} />}

      {delta && <DeltaBlock delta={delta} components={currentFuture.price.components} />}

      {!delta && !noSolution && !error && (
        <p className="simulator-empty">
          Пока ни одной симуляции. Разницу между версиями покажем здесь: что изменилось, чем за это заплачено,
          какие риски появились или ушли.
        </p>
      )}
    </section>
  );
}

function DeltaBlock({ delta, components }: { delta: Delta; components: PriceComponent[] }) {
  const arithmetic = checkArithmetic(delta);
  const changes = groupChanges(delta.dimension_changes);

  return (
    <section className="delta-block" aria-labelledby="delta-title">
      <div className="block-heading">
        <div>
          <span className="metric-label">Что изменилось</span>
          <h3 id="delta-title">Разница между версиями</h3>
        </div>
        <span className="number-basis">оценка, не оферта</span>
      </div>

      {delta.explanation && <p className="delta-explanation">{delta.explanation}</p>}

      <div className="delta-total">
        <span className="metric-label">Стоимость поездки</span>
        <p className="delta-total__line">
          <span className="delta-total__before">{formatMoney(delta.price_before)}</span>
          <span aria-hidden="true"> → </span>
          <span className="delta-total__after">{formatMoney(delta.price_after)}</span>
          <span className={changeClass("delta-total__change", delta.price_change)}>
            {formatSignedMoney(delta.price_change)}
          </span>
        </p>
        <PriceOrigin components={components} />
      </div>

      <div className="delta-items">
        {delta.items.length > 0 ? (
          delta.items.map((item, index) => <DeltaItemRow key={`${item.description}-${index}`} item={item} />)
        ) : (
          <p className="missing-data">
            Цена изменилась, но разложения на позиции не пришло — принять такое изменение на веру нельзя.
          </p>
        )}
      </div>

      <div className={arithmetic.exact ? "delta-sum" : "delta-sum delta-sum--broken"} role={arithmetic.exact ? undefined : "alert"}>
        <span>Сумма позиций</span>
        <strong className="delta-sum__value">{formatSignedMoney(arithmetic.itemsTotal)}</strong>
        <p className="delta-sum__verdict">
          {arithmetic.exact
            ? `Сходится с общим изменением ${formatSignedMoney(delta.price_change)}.`
            : arithmeticComplaint(arithmetic, delta)}
        </p>
      </div>

      <div className="delta-match">
        <span className="metric-label">Experience Match</span>
        <p className="delta-match__line">
          <span>{formatPercent(delta.match_before)}</span>
          <span aria-hidden="true"> → </span>
          <strong>{formatPercent(delta.match_after)}</strong>
          <span className={delta.match_after < delta.match_before ? "delta-match__change delta-match__change--negative" : "delta-match__change"}>
            {formatSignedPercentPoints(delta.match_after - delta.match_before)}
          </span>
        </p>
        {delta.dimension_changes.length > 0 ? (
          <ul className="delta-dimensions">
            {(["improved", "worsened", "unchanged"] as const).flatMap((change) =>
              changes[change].map((entry) => (
                <li key={entry.dimension} className={`delta-dimension delta-dimension--${change}`}>
                  <span className="delta-dimension__mark" aria-hidden="true">{CHANGE_MARKS[change]}</span>
                  <strong>{DIMENSION_LABELS[entry.dimension] || entry.dimension}</strong>
                  <span>{CHANGE_LABELS[change]}</span>
                </li>
              )),
            )}
          </ul>
        ) : (
          <p className="missing-data">
            Match изменился, но по каким измерениям — не сказано. Процент без разложения ничего не значит.
          </p>
        )}
      </div>

      <div className="delta-risks">
        <div>
          <span className="metric-label">Появились риски</span>
          <RiskList risks={delta.new_risks} emptyText="Новых рисков не появилось." tone="new" />
        </div>
        <div>
          <span className="metric-label">Сняты риски</span>
          <RiskList risks={delta.resolved_risks} emptyText="Ни один риск не снят." tone="resolved" />
        </div>
      </div>
    </section>
  );
}

function DeltaItemRow({ item }: { item: DeltaItem }) {
  return (
    <div className="delta-item">
      <div>
        <strong>{item.description}</strong>
        <span>
          {item.relaxed_dimension
            ? `Ослаблено предпочтение: ${DIMENSION_LABELS[item.relaxed_dimension] || item.relaxed_dimension}`
            : "Не сказано, какое предпочтение ослаблено"}
        </span>
      </div>
      <strong className={changeClass("delta-item__amount", item.amount)}>{formatSignedMoney(item.amount)}</strong>
    </div>
  );
}

function RiskList({ risks, emptyText, tone }: { risks: RiskSummary[]; emptyText: string; tone: "new" | "resolved" }) {
  if (risks.length === 0) return <p className="delta-risks__empty">{emptyText}</p>;
  return (
    <ul className={`delta-risk-list delta-risk-list--${tone}`}>
      {risks.map((risk) => (
        <li key={risk.id}>
          <strong>{RISK_LABELS[risk.risk_type] || risk.risk_type}</strong>
          <span>риск {SEVERITY_LABELS[risk.severity]}</span>
        </li>
      ))}
    </ul>
  );
}

function NoSolutionBlock({ noSolution }: { noSolution: NoSolution }) {
  return (
    <section className="no-solution" aria-labelledby="no-solution-title" role="region">
      <span className="metric-label">Так не получается</span>
      <h3 id="no-solution-title">Запрос выполнить нельзя</h3>
      <p className="no-solution__reason">{noSolution.reason}</p>

      <div className="no-solution__constraints">
        <span className="metric-label">Что не удалось удержать</span>
        {noSolution.unsatisfiable_constraints.length > 0 ? (
          <ul>
            {noSolution.unsatisfiable_constraints.map((dimension) => (
              <li key={dimension}>{DIMENSION_LABELS[dimension] || dimension}</li>
            ))}
          </ul>
        ) : (
          <p className="missing-data">Сервис не назвал ни одного ограничения — причина отказа непроверяема.</p>
        )}
      </div>

      <div className="no-solution__alternatives">
        <span className="metric-label">Ближайшее достижимое</span>
        <p className="no-solution__caveat">
          Это не то, о чём вы просили. Это ближайшее, что существует — выбор за вами.
        </p>
        {noSolution.nearest_alternatives.length > 0 ? (
          <div className="alternative-grid">
            {noSolution.nearest_alternatives.map((alternative) => (
              <AlternativeCard key={alternative.id} future={alternative} />
            ))}
          </div>
        ) : (
          <p className="missing-data">Ближайших вариантов тоже нет — предложить нечего.</p>
        )}
      </div>
    </section>
  );
}

function AlternativeCard({ future }: { future: Future }) {
  const contributions = future.match.contributions
    .slice()
    .sort((left, right) => Math.abs(right.contribution) - Math.abs(left.contribution))
    .slice(0, 2);
  const hasPriceBreakdown = future.price.components.length > 0
    && future.price.components.every((component) => Boolean(component.fulfilment));

  return (
    <article className="alternative-card">
      <h4>{future.destination.name}</h4>
      <p className="alternative-card__stay">
        {future.accommodation.name} · {formatDate(future.check_in)} — {formatDate(future.check_out)}
      </p>
      {hasPriceBreakdown ? (
        <p className="alternative-card__price">{formatMoney(future.price.total)}</p>
      ) : (
        <p className="missing-data">Итог не показываем без разбиения на наблюдаемые и моделируемые части.</p>
      )}
      {hasPriceBreakdown && <PriceOrigin components={future.price.components} />}
      {contributions.length > 0 ? (
        <div className="alternative-card__match">
          <strong>Match {formatPercent(future.match.score)}</strong>
          <ul>
            {contributions.map((contribution) => (
              <li key={contribution.dimension}>
                {DIMENSION_LABELS[contribution.dimension] || contribution.dimension}: {contributionText(contribution)}
              </li>
            ))}
          </ul>
        </div>
      ) : (
        <p className="missing-data">Match нельзя показать без вкладов по измеренным предпочтениям.</p>
      )}
    </article>
  );
}

// The room rate is modeled and the fares are observed (rule 7). A delta that mixes them has to say so.
function PriceOrigin({ components }: { components: PriceComponent[] }) {
  if (components.length === 0) {
    return <p className="missing-data">Происхождение суммы неизвестно: разбиения по компонентам нет.</p>;
  }

  const observed = components.filter((component) => component.fulfilment === "estimate");
  const modeled = components.filter((component) => component.fulfilment === "modeled");

  return (
    <p className="price-origin">
      {observed.length > 0 && (
        <span className="basis basis--estimate">
          наблюдаемые: {observed.map((component) => COMPONENT_LABELS[component.kind]).join(", ")}
        </span>
      )}
      {modeled.length > 0 && (
        <span className="basis basis--modeled">
          моделируемые: {modeled.map((component) => COMPONENT_LABELS[component.kind]).join(", ")}
        </span>
      )}
      {observed.length > 0 && modeled.length > 0 && (
        <small>Изменение смешивает наблюдаемые и моделируемые части.</small>
      )}
    </p>
  );
}

type Arithmetic = {
  itemsTotal: Money;
  itemsMatchChange: boolean;
  endpointsMatchChange: boolean;
  singleCurrency: boolean;
  exact: boolean;
};

// The arithmetic being exact is the product's claim, so it is checked in the UI rather than assumed.
export function checkArithmetic(delta: Delta): Arithmetic {
  const itemsTotalMinor = delta.items.reduce((sum, item) => sum + item.amount.amount_minor, 0);
  const currencies = new Set([
    delta.price_before.currency,
    delta.price_after.currency,
    delta.price_change.currency,
    ...delta.items.map((item) => item.amount.currency),
  ]);
  const singleCurrency = currencies.size === 1;
  const itemsMatchChange = itemsTotalMinor === delta.price_change.amount_minor;
  const endpointsMatchChange =
    delta.price_after.amount_minor - delta.price_before.amount_minor === delta.price_change.amount_minor;

  return {
    itemsTotal: { amount_minor: itemsTotalMinor, currency: delta.price_change.currency },
    itemsMatchChange,
    endpointsMatchChange,
    singleCurrency,
    exact: itemsMatchChange && endpointsMatchChange && singleCurrency,
  };
}

function arithmeticComplaint(arithmetic: Arithmetic, delta: Delta) {
  const problems: string[] = [];

  if (!arithmetic.itemsMatchChange) {
    const gap: Money = {
      amount_minor: arithmetic.itemsTotal.amount_minor - delta.price_change.amount_minor,
      currency: delta.price_change.currency,
    };
    problems.push(
      `позиции дают ${formatSignedMoney(arithmetic.itemsTotal)}, а общее изменение — ${formatSignedMoney(delta.price_change)}; расхождение ${formatSignedMoney(gap)}`,
    );
  }
  if (!arithmetic.endpointsMatchChange) {
    problems.push(
      `${formatMoney(delta.price_before)} → ${formatMoney(delta.price_after)} не даёт ${formatSignedMoney(delta.price_change)}`,
    );
  }
  if (!arithmetic.singleCurrency) {
    problems.push("позиции пришли в разных валютах, складывать их нельзя");
  }

  return `Арифметика не сходится: ${problems.join("; ")}. Это ошибка расчёта, а не округление.`;
}

function groupChanges(changes: Delta["dimension_changes"]) {
  return {
    improved: changes.filter((entry) => entry.change === "improved"),
    worsened: changes.filter((entry) => entry.change === "worsened"),
    unchanged: changes.filter((entry) => entry.change === "unchanged"),
  };
}

function contributionText(contribution: MatchContribution) {
  return contribution.explanation || `совпадение ${formatPercent(contribution.satisfaction)}`;
}

function changeClass(base: string, amount: Money) {
  if (amount.amount_minor < 0) return `${base} ${base}--saving`;
  if (amount.amount_minor > 0) return `${base} ${base}--cost`;
  return base;
}

function magnitude(step: number, steps: number) {
  return Math.min(1, Number((step * Math.abs(steps)).toFixed(2)));
}

function sidePosition(steps: number, leftWord: string, rightWord: string) {
  if (steps === 0) return "без изменений";
  const word = steps > 0 ? rightWord : leftWord;
  return `${Math.abs(steps)} ${pluralSteps(Math.abs(steps))} ${word}`;
}

function pluralSteps(count: number) {
  if (count === 1) return "шаг";
  if (count < 5) return "шага";
  return "шагов";
}

function pluralAdjustments(count: number) {
  if (count === 1) return "изменение";
  if (count < 5) return "изменения";
  return "изменений";
}

function formatMoney(money: Money) {
  return new Intl.NumberFormat("ru-RU", { style: "currency", currency: money.currency, maximumFractionDigits: 0 })
    .format(Math.abs(money.amount_minor) / MINOR_UNITS_PER_MAJOR_UNIT);
}

function formatSignedMoney(money: Money) {
  const sign = money.amount_minor < 0 ? "−" : money.amount_minor > 0 ? "+" : "";
  return `${sign}${formatMoney(money)}`;
}

function formatPercent(value: number) {
  return `${Math.round(clamp(value) * 100)}%`;
}

function formatSignedPercentPoints(delta: number) {
  const points = Math.round(delta * 100);
  if (points === 0) return "без изменений";
  return `${points < 0 ? "−" : "+"}${Math.abs(points)} п.п.`;
}

function formatNumber(value: number) {
  return new Intl.NumberFormat("ru-RU", { maximumFractionDigits: 2 }).format(value);
}

function formatDate(date: string) {
  return new Intl.DateTimeFormat("ru-RU", { day: "numeric", month: "short" })
    .format(new Date(`${date}T00:00:00`));
}

function clamp(value: number) {
  return Math.min(1, Math.max(0, value));
}

function errorMessage(error: unknown) {
  if (error instanceof ApiProblem) return error.message;
  if (error instanceof TypeError) return "Сервис недоступен. Проверьте подключение и попробуйте ещё раз.";
  if (error instanceof Error) return error.message;
  return "Произошла неизвестная ошибка. Попробуйте ещё раз.";
}
