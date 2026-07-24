import { useEffect, useState } from "react";
import type {
  Future,
  Logistics,
  MatchContribution,
  PriceComponent,
  TravelLeg,
} from "../generated/client";

type FuturesViewProps = {
  futures: Future[];
  diversityNote?: string | null;
  // Choosing is what turns a comparison into a plan. Identity is by lineage, not by version: a simulated
  // child is still the same Future the user picked.
  chosenId?: string | null;
  onChoose?: (future: Future) => void;
};

const DIMENSION_LABELS: Record<string, string> = {
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

const TRANSFER_LABELS: Record<Logistics["airport_transfer"]["mode"], string> = {
  private: "индивидуальный",
  shared: "сборный",
  public: "общественный транспорт",
  walk: "пешком",
};

const RUB_MINOR_UNITS_PER_MAJOR_UNIT = 100;

export function FuturesView({ futures, diversityNote, chosenId = null, onChoose }: FuturesViewProps) {
  return (
    <section className="futures-section" aria-labelledby="futures-title">
      <div className="futures-heading">
        <div>
          <span className="result-kicker">03 · Возможные будущие</span>
          <h2 id="futures-title">Не список отелей, а три разных сценария</h2>
        </div>
        <p>
          Каждый вариант — цельная поездка. Сначала смотрите, что подходит по ощущениям, затем — какой компромисс
          за это принимаете.
        </p>
      </div>

      {diversityNote && <p className="diversity-note" role="status">{diversityNote}</p>}

      <div className="future-grid">
        {futures.map((future, index) => (
          <FutureCard
            key={future.id}
            future={future}
            index={index}
            isChosen={chosenId === future.lineage_id}
            onChoose={onChoose}
          />
        ))}
      </div>
    </section>
  );
}

function FutureCard({ future, index, isChosen, onChoose }: {
  future: Future;
  index: number;
  isChosen?: boolean;
  onChoose?: (future: Future) => void;
}) {
  const [now, setNow] = useState(() => Date.now());
  const hasPriceBreakdown = future.price.components.length > 0
    && future.price.components.every((component) => Boolean(component.fulfilment));
  const contributions = future.match.contributions
    .slice()
    .sort((left, right) => Math.abs(right.contribution) - Math.abs(left.contribution));
  const topContributions = contributions.slice(0, 2);
  const hasMatchBreakdown = contributions.length > 0;
  useEffect(() => {
    const expiresAt = new Date(future.expires_at).getTime();
    const delay = Math.max(0, expiresAt - Date.now());
    if (delay === 0) return undefined;

    const timer = window.setTimeout(() => setNow(Date.now()), delay);
    return () => window.clearTimeout(timer);
  }, [future.expires_at]);

  const isExpired = now >= new Date(future.expires_at).getTime();

  return (
    <article className="future-card">
      <div className="future-card__topline">
        <span className="future-card__number">Будущее {String.fromCharCode(65 + index)}</span>
        <span className="future-card__version">Версия {future.version}</span>
      </div>

      <div className="future-card__destination">
        <div>
          <h3>{future.destination.name}</h3>
          <p>{future.destination.country}</p>
        </div>
        <span className="future-card__dates">
          {formatDate(future.check_in)} — {formatDate(future.check_out)}
        </span>
      </div>

      <p className={isExpired ? "plan-freshness plan-freshness--expired" : "plan-freshness"} role="status">
        {isExpired ? "План устарел" : "План актуален"} · расчёт создан {formatAge(future.created_at)}
        {isExpired ? "" : ` · действует до ${formatDateTime(future.expires_at)}`}
      </p>

      <section className="match-summary" aria-labelledby={`match-${future.id}`}>
        <div className="match-summary__score">
          <span className="metric-label" id={`match-${future.id}`}>Experience Match</span>
          {hasMatchBreakdown ? (
            <strong>{formatPercent(future.match.score)}</strong>
          ) : (
            <strong className="metric-unavailable">Нет данных</strong>
          )}
          <span className="metric-context">
            Покрытие {formatPercent(future.match.coverage)} · уверенность {formatPercent(future.match.confidence)}
          </span>
        </div>
        {hasMatchBreakdown && (
          <div className="match-meter" aria-hidden="true">
            <span style={{ width: `${clamp(future.match.score) * 100}%` }} />
          </div>
        )}
        {hasMatchBreakdown && (
          <div className="contribution-preview" aria-label="Главные вклады" role="region">
            {topContributions.map((contribution) => <ContributionRow key={contribution.dimension} contribution={contribution} />)}
          </div>
        )}
        {hasMatchBreakdown ? (
          <details className="evidence-details">
            <summary>Почему такой Match</summary>
            <div className="contribution-list">
              {contributions.map((contribution) => <ContributionRow key={contribution.dimension} contribution={contribution} />)}
            </div>
          </details>
        ) : (
          <p className="missing-data">Match нельзя показать без вкладов по измеренным предпочтениям.</p>
        )}
      </section>

      <section className="future-block price-block" aria-labelledby={`price-${future.id}`}>
        <div className="block-heading">
          <div>
            <span className="metric-label">Стоимость всей поездки</span>
            <h4 id={`price-${future.id}`}>
              {hasPriceBreakdown ? formatMoney(future.price.total) : "Итого пока неизвестно"}
            </h4>
          </div>
          <span className="number-basis">оценка, не оферта</span>
        </div>
        {hasPriceBreakdown ? (
          <div className="price-breakdown">
            {future.price.components.map((component) => <PriceRow key={component.kind} component={component} />)}
          </div>
        ) : (
          <p className="missing-data">Итог не показываем без разбиения на наблюдаемые и моделируемые части.</p>
        )}
      </section>

      <section className="future-block logistics-block" aria-labelledby={`logistics-${future.id}`}>
        <div className="block-heading">
          <div>
            <span className="metric-label">Как проходит поездка</span>
            <h4 id={`logistics-${future.id}`}>Логистика и место</h4>
          </div>
        </div>
        <div className="accommodation-summary">
          <strong>{future.accommodation.name}</strong>
          <span>{future.accommodation.room_name} · {seaDistance(future.accommodation.distance_to_sea_m)}</span>
        </div>
        <Leg leg={future.logistics.outbound} label="Туда" />
        <Leg leg={future.logistics.inbound} label="Обратно" />
        <div className="logistics-row">
          <span>Из аэропорта</span>
          <strong>{TRANSFER_LABELS[future.logistics.airport_transfer.mode]}, {future.logistics.airport_transfer.duration_min} мин</strong>
          {future.logistics.airport_transfer.note && <small>{future.logistics.airport_transfer.note}</small>}
        </div>
        <div className="logistics-row">
          <span>На месте</span>
          <strong>{future.logistics.local_mobility.assumption}</strong>
        </div>
      </section>

      <section className="future-block reason-block" aria-labelledby={`reason-${future.id}`}>
        <span className="metric-label">Зачем этот вариант</span>
        <h4 id={`reason-${future.id}`}>{future.why_this_exists}</h4>
        <div className="pros-cons">
          <div>
            <span>Что получите</span>
            <ul>{future.benefits.map((benefit) => <li key={benefit}>{benefit}</li>)}</ul>
          </div>
          <div>
            <span>Что отдаёте</span>
            <ul>{future.compromises.map((compromise) => <li key={compromise}>{compromise}</li>)}</ul>
          </div>
        </div>
      </section>

      <UnknownBlock future={future} />

      {onChoose && (
        <div className="future-card__actions">
          <button
            className={isChosen ? "secondary-action" : "primary-action"}
            type="button"
            aria-pressed={Boolean(isChosen)}
            onClick={() => onChoose(future)}
          >
            {isChosen ? "Выбрано — открыть план ниже" : "Взять это будущее"}
          </button>
        </div>
      )}
    </article>
  );
}

function ContributionRow({ contribution }: { contribution: MatchContribution }) {
  const isPenalty = contribution.contribution < 0;
  return (
    <div className="contribution-row">
      <div>
        <strong>{DIMENSION_LABELS[contribution.dimension] || contribution.dimension}</strong>
        <span>{contribution.explanation || `Совпадение ${formatPercent(contribution.satisfaction)}`}</span>
      </div>
      <b className={isPenalty ? "contribution-value contribution-value--negative" : "contribution-value"}>
        {isPenalty ? "−" : "+"}{formatPercent(Math.abs(contribution.contribution))}
      </b>
    </div>
  );
}

function PriceRow({ component }: { component: PriceComponent }) {
  return (
    <div className="price-row">
      <div>
        <strong>{COMPONENT_LABELS[component.kind]}</strong>
        <span className={`basis basis--${component.fulfilment}`}>
          {component.fulfilment === "estimate" ? "наблюдаемая оценка" : "моделируемая часть"}
        </span>
        <small>
          {component.source || "Источник не указан"}
          {component.as_of ? ` · на ${formatDateTime(component.as_of)}` : " · без даты наблюдения"}
        </small>
      </div>
      <strong>{formatMoney(component.amount)}</strong>
    </div>
  );
}

function Leg({ leg, label }: { leg: TravelLeg; label: string }) {
  return (
    <div className="leg-row">
      <div className="leg-row__label"><span>{label}</span><small>{leg.carrier || "Перевозчик не указан"}</small></div>
      <div><strong>{leg.origin} → {leg.destination}</strong><span>{formatDateTime(leg.depart_at)} — {formatDateTime(leg.arrive_at)}</span></div>
      <small>{leg.duration_min} мин · {stopsLabel(leg.stops)} · цена наблюдалась {formatDateTime(leg.as_of)}</small>
      {leg.booking_url && <a href={leg.booking_url} target="_blank" rel="noreferrer">Открыть перелёт ↗</a>}
    </div>
  );
}

function UnknownBlock({ future }: { future: Future }) {
  const unknowns = future.match.unscored_dimensions;
  return (
    <section className="unknown-block" aria-labelledby={`unknown-${future.id}`}>
      <div>
        <span className="metric-label">Граница знания</span>
        <h4 id={`unknown-${future.id}`}>Что мы пока не знаем</h4>
      </div>
      {unknowns.length > 0 ? (
        <ul>{unknowns.map((item) => <li key={item.dimension}><strong>{DIMENSION_LABELS[item.dimension] || item.dimension}:</strong> {item.reason}</li>)}</ul>
      ) : (
        <p>По заявленным предпочтениям нет необъяснённых пробелов в данных.</p>
      )}
      {future.match.coverage < 0.6 && <p className="coverage-warning">Покрытие ниже 60% — сравнивайте этот вариант осторожно.</p>}
    </section>
  );
}

function formatMoney(money: { amount_minor: number; currency: string }) {
  return new Intl.NumberFormat("ru-RU", { style: "currency", currency: money.currency, maximumFractionDigits: 0 })
    .format(money.amount_minor / RUB_MINOR_UNITS_PER_MAJOR_UNIT);
}

function formatPercent(value: number) {
  return `${Math.round(clamp(value) * 100)}%`;
}

function formatDate(date: string) {
  return new Intl.DateTimeFormat("ru-RU", { day: "numeric", month: "short", year: "numeric" })
    .format(new Date(`${date}T00:00:00`));
}

function formatDateTime(date: string) {
  const formatted = new Intl.DateTimeFormat("ru-RU", {
    day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "UTC",
  }).format(new Date(date));
  return `${formatted} UTC`;
}

function formatAge(date: string) {
  const elapsedMinutes = Math.max(0, Math.floor((Date.now() - new Date(date).getTime()) / 60_000));
  if (elapsedMinutes < 60) return `${elapsedMinutes} мин назад`;
  const hours = Math.floor(elapsedMinutes / 60);
  const minutes = elapsedMinutes % 60;
  return minutes === 0 ? `${hours} ч назад` : `${hours} ч ${minutes} мин назад`;
}

function seaDistance(distance: number | null) {
  if (distance === null) return "расстояние до моря неизвестно · источник не дал геометрию";
  const formatted = distance < 1000 ? `${distance} м до моря` : `${(distance / 1000).toFixed(1).replace(".", ",")} км до моря`;
  return `${formatted} · геоданные Supply`;
}

function stopsLabel(stops: number) {
  if (stops === 0) return "без пересадок";
  if (stops === 1) return "1 пересадка";
  return `${stops} пересадки`;
}

function clamp(value: number) {
  return Math.min(1, Math.max(0, value));
}
