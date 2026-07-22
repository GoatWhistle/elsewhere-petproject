import { useState, type ReactNode } from "react";
import type {
  Coverage,
  Dimension,
  Evidence,
  Forecast,
  Mitigation,
  Money,
  RiskItem,
  RiskType,
  Severity,
} from "../generated/client";
import "./ForecastPanel.css";

type ForecastPanelProps = {
  forecast: Forecast | null;
  isLoading: boolean;
  error: string | null;
  onFixRisk: (riskId: string, mitigationId: string) => Promise<void>;
};

// The contract's full risk vocabulary. The denominator of "оценено N из 9" comes from here and not from the
// length of the coverage array: a type the server forgot to mention is an unchecked type, not a missing row.
const ALL_RISK_TYPES: RiskType[] = [
  "night_noise",
  "crowds",
  "walkability",
  "weather_mismatch",
  "construction",
  "transfer_difficulty",
  "weak_transport",
  "room_location_mismatch",
  "seasonal_closure",
];

const RISK_TYPE_LABELS: Record<RiskType, string> = {
  night_noise: "Ночной шум",
  crowds: "Толпы людей",
  walkability: "Пешая доступность",
  weather_mismatch: "Погода не та",
  construction: "Стройка рядом",
  transfer_difficulty: "Сложный трансфер",
  weak_transport: "Слабый транспорт",
  room_location_mismatch: "Номер или расположение не те",
  seasonal_closure: "Сезонные закрытия",
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

const SEVERITY_LABELS: Record<Severity, string> = {
  low: "низкая",
  medium: "средняя",
  high: "высокая",
};

const SEVERITY_STEPS: Record<Severity, number> = { low: 1, medium: 2, high: 3 };

// DEC-030: confidence follows from the kind of claim. The label says which kind it is, the note says what that
// kind is worth — an inference must never be readable as a measurement.
const CLAIM_KIND_LABELS: Record<RiskItem["claim_kind"], string> = {
  verified_fact: "измеренный факт",
  derived_metric: "расчёт по данным",
  model_inference: "предположение модели",
};

const CLAIM_KIND_NOTES: Record<RiskItem["claim_kind"], string> = {
  verified_fact: "Величина измерена, а не выведена.",
  derived_metric: "Посчитано из наблюдённых данных по правилу, а не измерено напрямую.",
  model_inference: "Это вывод, а не измерение. Он может не подтвердиться — проверьте основание ниже.",
};

const EVIDENCE_SOURCE_LABELS: Record<Evidence["source"], string> = {
  review: "отзывы",
  geo: "гео-измерение",
  weather: "погодные данные",
  seasonality: "сезонность",
  provider_metadata: "данные поставщика",
};

const RUB_MINOR_UNITS_PER_MAJOR_UNIT = 100;
const STALE_EVIDENCE_DAYS = 365;
const MILLISECONDS_PER_DAY = 86_400_000;

export function ForecastPanel({ forecast, isLoading, error, onFixRisk }: ForecastPanelProps) {
  if (isLoading) {
    return (
      <PanelShell busy>
        <p className="forecast-status" role="status">
          Проверяем риски и собираем основания для каждого…
        </p>
      </PanelShell>
    );
  }

  // "Не смогли посчитать" и "посчитали, рисков нет" — разные вещи, и пользователь должен видеть, какая из них.
  if (error) {
    return (
      <PanelShell>
        <div className="forecast-failure" role="alert">
          <h3>Прогноз не построен</h3>
          <p>{error}</p>
          <p className="forecast-failure__caveat">
            Это не значит, что рисков нет — значит, что мы их не проверили. Ни один тип риска для этого варианта
            не оценён.
          </p>
        </div>
      </PanelShell>
    );
  }

  if (!forecast) {
    return (
      <PanelShell>
        <p className="forecast-status" role="status">
          Прогноз для этого будущего ещё не запрашивался.
        </p>
      </PanelShell>
    );
  }

  const rows = coverageRows(forecast.coverage);
  const assessed = rows.filter((row) => row.assessed);
  const gaps = rows.filter((row) => !row.assessed);

  return (
    <PanelShell>
      <p className="forecast-scope">
        Оценено <strong>{assessed.length} из {ALL_RISK_TYPES.length}</strong> типов рисков ·
        прогноз собран {formatDateTime(forecast.generated_at)}
      </p>
      <p className="forecast-axes">
        Серьёзность и уверенность — разные шкалы. «Скорее всего обойдётся, но будет плохо» и «точно, но мелочь»
        здесь выглядят по-разному и требуют разных решений.
      </p>

      <div className="forecast-columns">
        <div className="forecast-risks">
          <h3 className="forecast-column-title" id="forecast-risks-title">
            Что мы нашли
          </h3>
          {forecast.risks.length > 0 ? (
            <div className="risk-list" aria-labelledby="forecast-risks-title">
              {forecast.risks.map((risk) => <RiskCard key={risk.id} risk={risk} onFixRisk={onFixRisk} />)}
            </div>
          ) : (
            <div className="risk-empty">
              <p>
                Среди проверенных типов рисков ни один не превысил порог для ваших предпочтений.
              </p>
              <p className="risk-empty__caveat">
                Это не «рисков нет»: непроверенными остались {gaps.length} из {ALL_RISK_TYPES.length} типов —
                они перечислены рядом.
              </p>
            </div>
          )}
        </div>

        <CoverageBlock assessed={assessed} gaps={gaps} />
      </div>
    </PanelShell>
  );
}

function PanelShell({ children, busy = false }: { children: ReactNode; busy?: boolean }) {
  return (
    <section className="forecast-panel" aria-labelledby="forecast-title" aria-busy={busy || undefined}>
      <div className="forecast-heading">
        <div>
          <span className="result-kicker">04 · Прогноз впечатления</span>
          <h2 id="forecast-title">Что может пойти не так именно у вас</h2>
        </div>
        <p>
          Не рейтинг и не стена отзывов. Каждый риск здесь назван вместе с тем, откуда он взялся, насколько
          серьёзен и насколько мы в нём уверены.
        </p>
      </div>
      {children}
    </section>
  );
}

function RiskCard({
  risk,
  onFixRisk,
}: {
  risk: RiskItem;
  onFixRisk: (riskId: string, mitigationId: string) => Promise<void>;
}) {
  const [applyingId, setApplyingId] = useState<string | null>(null);
  const [failure, setFailure] = useState<string | null>(null);
  const mitigations = risk.mitigations ?? [];
  const isInference = risk.claim_kind === "model_inference";

  const handleFix = async (mitigationId: string) => {
    setFailure(null);
    setApplyingId(mitigationId);
    try {
      await onFixRisk(risk.id, mitigationId);
    } catch {
      setFailure("Не удалось применить решение. Будущее осталось прежним.");
    } finally {
      setApplyingId(null);
    }
  };

  return (
    <article
      className={isInference ? "risk-card risk-card--inference" : "risk-card"}
      aria-busy={applyingId !== null || undefined}
    >
      <div className="risk-card__topline">
        <h4 id={`risk-${risk.id}`}>{RISK_TYPE_LABELS[risk.risk_type]}</h4>
        <span className={`claim-kind claim-kind--${risk.claim_kind}`}>{CLAIM_KIND_LABELS[risk.claim_kind]}</span>
      </div>

      <p className="risk-statement">{risk.statement}</p>
      <p className="claim-note">{CLAIM_KIND_NOTES[risk.claim_kind]}</p>
      {risk.risk_type === "night_noise" && risk.claim_kind !== "verified_fact" && (
        <p className="claim-note claim-note--proxy">
          Шум никто не измерял. Это оценка по расстоянию до дороги — косвенный признак, а не показание.
        </p>
      )}

      <div className="risk-axes">
        <div className="risk-axis risk-axis--severity">
          <span className="metric-label">Серьёзность</span>
          <strong>{SEVERITY_LABELS[risk.severity]}</strong>
          <span className={`severity-steps severity-steps--${risk.severity}`} aria-hidden="true">
            {[1, 2, 3].map((step) => (
              <i key={step} className={step <= SEVERITY_STEPS[risk.severity] ? "is-filled" : undefined} />
            ))}
          </span>
          <small>насколько плохо, если случится</small>
        </div>
        <div className="risk-axis risk-axis--confidence">
          <span className="metric-label">Уверенность</span>
          <strong>{formatPercent(risk.confidence)}</strong>
          <span className="confidence-meter" aria-hidden="true">
            <span style={{ width: `${clamp(risk.confidence) * 100}%` }} />
          </span>
          <small>насколько основание это подтверждает</small>
        </div>
      </div>

      <p className="risk-dimension">
        Задевает предпочтение: <strong>{DIMENSION_LABELS[risk.affected_dimension] || risk.affected_dimension}</strong>
      </p>

      <section className="risk-evidence" aria-labelledby={`evidence-${risk.id}`}>
        <h5 id={`evidence-${risk.id}`}>Основание</h5>
        {risk.evidence.map((evidence, index) => (
          <EvidenceRow key={`${evidence.source}-${index}`} evidence={evidence} />
        ))}
      </section>

      {mitigations.length > 0 && (
        <section className="risk-mitigations" aria-labelledby={`mitigations-${risk.id}`}>
          <h5 id={`mitigations-${risk.id}`}>Как это можно снять</h5>
          {mitigations.map((mitigation) => (
            <MitigationRow
              key={mitigation.id}
              mitigation={mitigation}
              severityBefore={risk.severity}
              isApplying={applyingId === mitigation.id}
              isDisabled={applyingId !== null}
              onApply={() => handleFix(mitigation.id)}
            />
          ))}
          <p className="mitigation-caveat">
            Решение не правит этот вариант, а создаёт новую версию будущего — прежнюю всегда можно вернуть.
          </p>
        </section>
      )}

      {failure && <p className="risk-error" role="alert">{failure}</p>}
    </article>
  );
}

function EvidenceRow({ evidence }: { evidence: Evidence }) {
  const observedAt = formatObservedAt(evidence.observed_at);
  return (
    <div className="evidence-row">
      <span className={`evidence-source evidence-source--${evidence.source}`}>
        {EVIDENCE_SOURCE_LABELS[evidence.source]}
      </span>
      <p>{evidence.excerpt || "Источник не передал формулировку наблюдения."}</p>
      <small>
        {observedAt ? `наблюдение от ${observedAt}` : "дата наблюдения неизвестна — свежесть не подтверждена"}
        {typeof evidence.count === "number" ? ` · упоминаний: ${evidence.count}` : ""}
        {isStale(evidence.observed_at) ? " · наблюдение старше года" : ""}
      </small>
    </div>
  );
}

// Цена и новая серьёзность стоят рядом с кнопкой, до нажатия: решение стоит денег и меняет будущее,
// поэтому пользователь видит обе цифры прежде, чем соглашается.
function MitigationRow({
  mitigation,
  severityBefore,
  isApplying,
  isDisabled,
  onApply,
}: {
  mitigation: Mitigation;
  severityBefore: Severity;
  isApplying: boolean;
  isDisabled: boolean;
  onApply: () => void;
}) {
  return (
    <div className="mitigation-row" aria-busy={isApplying || undefined}>
      <div className="mitigation-row__body">
        <strong>{mitigation.description}</strong>
        <span className="mitigation-price">{formatMoneyChange(mitigation.price_change)}</span>
        <span className="mitigation-severity">
          серьёзность {SEVERITY_LABELS[severityBefore]} → {SEVERITY_LABELS[mitigation.severity_after]}
        </span>
      </div>
      <button className="secondary-action" type="button" disabled={isDisabled} onClick={onApply}>
        {isApplying ? "Пересчитываем будущее…" : "Устранить риск"}
      </button>
    </div>
  );
}

// DEC-031 / DEC-021: пробелы покрытия стоят рядом с рисками отдельным блоком, а не мелким шрифтом внизу.
function CoverageBlock({ assessed, gaps }: { assessed: Coverage[]; gaps: Coverage[] }) {
  return (
    <section className="coverage-block" aria-labelledby="coverage-title">
      <span className="metric-label">Граница прогноза</span>
      <h3 id="coverage-title">Чего мы не проверяли</h3>
      <p className="coverage-block__lead">
        {gaps.length > 0
          ? `${gaps.length} из ${ALL_RISK_TYPES.length} типов рисков не оценены вообще. Отсутствие проверки — не отсутствие риска.`
          : "Все типы рисков из справочника были оценены."}
      </p>

      {gaps.length > 0 && (
        <ul className="coverage-gaps">
          {gaps.map((gap) => (
            <li key={gap.risk_type}>
              <strong>{RISK_TYPE_LABELS[gap.risk_type]}</strong>
              <span>{gap.reason || "Причина не указана — считаем тип непроверенным."}</span>
            </li>
          ))}
        </ul>
      )}

      <div className="coverage-assessed">
        <span className="metric-label">Проверено</span>
        {assessed.length > 0 ? (
          <ul>
            {assessed.map((row) => <li key={row.risk_type}>{RISK_TYPE_LABELS[row.risk_type]}</li>)}
          </ul>
        ) : (
          <p>Ни один тип риска не был оценён.</p>
        )}
      </div>
    </section>
  );
}

function coverageRows(coverage: Coverage[]): Coverage[] {
  const byType = new Map(coverage.map((row) => [row.risk_type, row]));
  return ALL_RISK_TYPES.map((riskType) => byType.get(riskType) ?? { risk_type: riskType, assessed: false });
}

function formatPercent(value: number) {
  return `${Math.round(clamp(value) * 100)}%`;
}

function formatMoney(money: Money) {
  return new Intl.NumberFormat("ru-RU", { style: "currency", currency: money.currency, maximumFractionDigits: 0 })
    .format(money.amount_minor / RUB_MINOR_UNITS_PER_MAJOR_UNIT);
}

function formatMoneyChange(money: Money) {
  if (money.amount_minor === 0) return "цена не меняется";
  const sign = money.amount_minor < 0 ? "−" : "+";
  return `${sign}${formatMoney({ ...money, amount_minor: Math.abs(money.amount_minor) })}`;
}

function formatObservedAt(observedAt: string | null | undefined) {
  const parsed = parseObservedAt(observedAt);
  if (!parsed) return null;
  return new Intl.DateTimeFormat("ru-RU", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" })
    .format(parsed);
}

function isStale(observedAt: string | null | undefined) {
  const parsed = parseObservedAt(observedAt);
  if (!parsed) return false;
  return (Date.now() - parsed.getTime()) / MILLISECONDS_PER_DAY > STALE_EVIDENCE_DAYS;
}

function parseObservedAt(observedAt: string | null | undefined) {
  if (!observedAt) return null;
  const parsed = new Date(observedAt.includes("T") ? observedAt : `${observedAt}T00:00:00Z`);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function formatDateTime(date: string) {
  const parsed = new Date(date);
  if (Number.isNaN(parsed.getTime())) return "без отметки времени";
  const formatted = new Intl.DateTimeFormat("ru-RU", {
    day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "UTC",
  }).format(parsed);
  return `${formatted} UTC`;
}

function clamp(value: number) {
  return Math.min(1, Math.max(0, value));
}
