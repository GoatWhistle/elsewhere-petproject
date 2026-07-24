import { useEffect, useState } from "react";
import type { Future, Logistics, PriceComponent, TravelLeg } from "../generated/client";
import "./TripPlan.css";

export type TripPlanProps = {
  future: Future;
};

// A Future card exists to be compared against two others at a glance. This screen exists to be read
// before acting: one trip, in the order it happens, at reading density.

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

// Where each number comes from, stated per component. DEC-029: only the accommodation *base* was
// observed — the seasonal factor is our hypothesis, and saying otherwise would be the one dishonest
// thing this product can do.
const MODELED_BASIS: Record<PriceComponent["kind"], string> = {
  travel: "Смоделировано нами — это не тариф, который кто-то показал.",
  accommodation:
    "Базовый уровень цен этого объекта наблюдался при сборе каталога. Сезонный коэффициент мы не наблюдали — "
    + "это наша модель: теплее и людней значит дороже.",
  transfer: "Наша модель: тип трансфера и заданное основание расчёта.",
  local_mobility: "Это допущение о ваших передвижениях, а не измерение.",
};

const OBSERVED_BASIS: Record<PriceComponent["kind"], string> = {
  travel: "Живой тариф, наблюдавшийся у источника.",
  accommodation: "Цена объекта, наблюдавшаяся у источника.",
  transfer: "Цена трансфера, наблюдавшаяся у источника.",
  local_mobility: "Цена проезда, наблюдавшаяся у источника.",
};

const RUB_MINOR_UNITS_PER_MAJOR_UNIT = 100;
const MILLISECONDS_PER_DAY = 86_400_000;

export function TripPlan({ future }: TripPlanProps) {
  const isOutdated = useOutdated(future.expires_at);
  const components = future.price.components;
  // The total is not renderable without its observed/modeled split (DEC-031).
  const hasOriginSplit = components.length > 0 && components.every((component) => Boolean(component.fulfilment));
  const split = hasOriginSplit ? originSplit(components, future.price.total.currency) : null;
  const nights = nightsBetween(future.check_in, future.check_out);

  return (
    <article className="trip-plan" aria-labelledby={`trip-plan-${future.id}`}>
      <header className="trip-plan__header">
        <span className="result-kicker">План поездки</span>
        <h2 id={`trip-plan-${future.id}`}>
          {future.destination.name}, {future.destination.country}
        </h2>
        <p className="trip-plan__summary">
          {formatDate(future.check_in)} — {formatDate(future.check_out)} · {nightsLabel(nights)} ·{" "}
          {future.accommodation.name}
        </p>

        <p
          className={isOutdated ? "plan-freshness plan-freshness--expired" : "plan-freshness"}
          role="status"
        >
          {isOutdated ? "План устарел" : "План актуален"} · расчёт создан {formatAge(future.created_at)}
          {isOutdated
            ? " · данные старше срока годности плана, запросите пересчёт, прежде чем действовать"
            : ` · действует до ${formatDateTime(future.expires_at)}`}
        </p>

        <p className="trip-plan__disclaimer">
          Elsewhere ничего не бронирует и не принимает оплату. Это план — маршрут, жильё, трансфер и оценка
          расходов; исполняете его вы сами.
        </p>
      </header>

      <section className="trip-plan__section" aria-labelledby={`travel-${future.id}`}>
        <div className="trip-plan__section-heading">
          <span className="trip-plan__step">01</span>
          <h3 id={`travel-${future.id}`}>Как вы туда добираетесь</h3>
        </div>
        <p className="trip-plan__note">
          Время рейсов — UTC. Местное время аэропортов не показываем: часового пояса в данных о рейсе нет,
          и пересчитывать его наугад значит выдумать число.
        </p>
        <ol className="trip-plan__legs">
          <li>
            <LegDetail leg={future.logistics.outbound} label="Туда" futureId={future.id} />
          </li>
          <li>
            <LegDetail leg={future.logistics.inbound} label="Обратно" futureId={future.id} />
          </li>
        </ol>
      </section>

      <section className="trip-plan__section" aria-labelledby={`stay-${future.id}`}>
        <div className="trip-plan__section-heading">
          <span className="trip-plan__step">02</span>
          <h3 id={`stay-${future.id}`}>Где вы живёте и какие ночи</h3>
        </div>
        <dl className="trip-plan__facts">
          <div>
            <dt>Объект</dt>
            <dd>{future.accommodation.name}</dd>
          </div>
          <div>
            <dt>Номер</dt>
            <dd>{future.accommodation.room_name}</dd>
          </div>
          <div>
            <dt>Заезд</dt>
            <dd>{formatDate(future.check_in)}</dd>
          </div>
          <div>
            <dt>Выезд</dt>
            <dd>{formatDate(future.check_out)}</dd>
          </div>
          <div>
            <dt>Ночей</dt>
            <dd>{nightsLabel(nights)}</dd>
          </div>
          <div>
            <dt>До моря</dt>
            <dd>{seaDistance(future.accommodation.distance_to_sea_m)}</dd>
          </div>
          {typeof future.accommodation.distance_to_centre_m === "number" && (
            <div>
              <dt>До центра</dt>
              <dd>{formatDistance(future.accommodation.distance_to_centre_m)} · геоданные Supply</dd>
            </div>
          )}
          <div>
            <dt>Отмена</dt>
            <dd>
              {future.accommodation.cancellation
                ? `${future.accommodation.cancellation.summary} · по данным каталога, не проверялось у объекта`
                : "Условия отмены нам не приходили — уточняйте у объекта"}
            </dd>
          </div>
        </dl>
        {future.accommodation.handoff_url && (
          <a
            className="trip-plan__link"
            href={future.accommodation.handoff_url}
            target="_blank"
            rel="noreferrer"
          >
            Открыть страницу объекта ↗
          </a>
        )}
      </section>

      <section className="trip-plan__section" aria-labelledby={`transfer-${future.id}`}>
        <div className="trip-plan__section-heading">
          <span className="trip-plan__step">03</span>
          <h3 id={`transfer-${future.id}`}>Из аэропорта до места и обратно</h3>
        </div>
        <dl className="trip-plan__facts">
          <div>
            <dt>Способ</dt>
            <dd>{TRANSFER_LABELS[future.logistics.airport_transfer.mode]}</dd>
          </div>
          <div>
            <dt>В пути</dt>
            <dd>{formatDuration(future.logistics.airport_transfer.duration_min)}</dd>
          </div>
          {future.logistics.airport_transfer.note && (
            <div>
              <dt>Основание</dt>
              <dd>{future.logistics.airport_transfer.note}</dd>
            </div>
          )}
        </dl>
        <p className="trip-plan__note">
          Дорога назад в аэропорт считается такой же: отдельного наблюдения на неё у нас нет.
        </p>
      </section>

      <section className="trip-plan__section" aria-labelledby={`mobility-${future.id}`}>
        <div className="trip-plan__section-heading">
          <span className="trip-plan__step">04</span>
          <h3 id={`mobility-${future.id}`}>Как вы передвигаетесь на месте</h3>
        </div>
        <p className="trip-plan__mobility">{future.logistics.local_mobility.assumption}</p>
        <p className="trip-plan__note">
          {future.logistics.local_mobility.walkable === undefined
            ? "Пешая доступность не оценивалась."
            : future.logistics.local_mobility.walkable
              ? "Пешую доступность показывают геоданные Supply."
              : "Геоданные Supply говорят, что пешком обойтись не выйдет."}
          {" "}Это допущение о поездке, а не расписание: расходы на месте посчитаны по нему.
        </p>
      </section>

      <section className="trip-plan__section" aria-labelledby={`cost-${future.id}`}>
        <div className="trip-plan__section-heading">
          <span className="trip-plan__step">05</span>
          <h3 id={`cost-${future.id}`}>Во что это обойдётся</h3>
        </div>

        {hasOriginSplit ? (
          <>
            <table className="trip-plan__costs">
              <caption>Оценка расходов на поездку. Каждая строка называет происхождение своего числа.</caption>
              <thead>
                <tr>
                  <th scope="col">Составляющая</th>
                  <th scope="col">Происхождение</th>
                  <th scope="col" className="trip-plan__amount-column">Сумма</th>
                </tr>
              </thead>
              <tbody>
                {components.map((component) => (
                  <CostRow key={component.kind} component={component} />
                ))}
              </tbody>
              <tfoot>
                <tr>
                  <th scope="row">Оценка всей поездки</th>
                  <td>оценка, не оферта и не цена, которую кто-то нам назвал</td>
                  <td className="trip-plan__amount-column">
                    <strong>{formatMoney(future.price.total)}</strong>
                  </td>
                </tr>
              </tfoot>
            </table>

            {split && (
              <p className="trip-plan__note">
                Из этой оценки {formatMoney({ amount_minor: split.observed, currency: split.currency })} —
                наблюдаемые цены, {formatMoney({ amount_minor: split.modeled, currency: split.currency })} —
                моделируемые нами.
              </p>
            )}
            <p className="trip-plan__estimate-note">
              Итог — оценка расходов, как в любом бюджете поездки. Цены живут своей жизнью и меняются между
              расчётом и вашим действием.
            </p>
          </>
        ) : (
          <p className="missing-data">
            Итог не показываем без разбиения на наблюдаемые и моделируемые части.
          </p>
        )}
      </section>

      <section className="trip-plan__section" aria-labelledby={`tradeoffs-${future.id}`}>
        <div className="trip-plan__section-heading">
          <span className="trip-plan__step">06</span>
          <h3 id={`tradeoffs-${future.id}`}>На что вы согласились, выбрав этот вариант</h3>
        </div>
        <p className="trip-plan__reason">{future.why_this_exists}</p>
        <div className="trip-plan__tradeoffs">
          <div>
            <h4>Что отдаёте</h4>
            {future.compromises.length > 0 ? (
              <ul className="trip-plan__compromises">
                {future.compromises.map((compromise) => <li key={compromise}>{compromise}</li>)}
              </ul>
            ) : (
              <p className="missing-data">Компромиссы этого варианта не были названы.</p>
            )}
          </div>
          <div>
            <h4>Что получаете взамен</h4>
            {future.benefits.length > 0 ? (
              <ul className="trip-plan__benefits">
                {future.benefits.map((benefit) => <li key={benefit}>{benefit}</li>)}
              </ul>
            ) : (
              <p className="missing-data">Преимущества этого варианта не были названы.</p>
            )}
          </div>
        </div>
      </section>

      <footer className="trip-plan__footer">
        <p>
          Ссылки на этой странице — удобство для того, кто решил ехать: они ведут к поставщику, у которого вы
          оформляете всё сами. Elsewhere не участвует в этой сделке и ничего с неё не получает.
        </p>
      </footer>
    </article>
  );
}

function LegDetail({ leg, label, futureId }: { leg: TravelLeg; label: string; futureId: string }) {
  const headingId = `leg-${label}-${futureId}`;

  return (
    <section className="trip-plan__leg" aria-labelledby={headingId}>
      <h4 id={headingId}>
        {label}: {leg.origin} → {leg.destination}
      </h4>
      <dl className="trip-plan__facts">
        <div>
          <dt>Вылет</dt>
          <dd>{formatDateTime(leg.depart_at)}</dd>
        </div>
        <div>
          <dt>Прилёт</dt>
          <dd>{formatDateTime(leg.arrive_at)}</dd>
        </div>
        <div>
          <dt>В пути</dt>
          <dd>{formatDuration(leg.duration_min)} · {stopsLabel(leg.stops)}</dd>
        </div>
        <div>
          <dt>Перевозчик</dt>
          <dd>{leg.carrier || "Перевозчик не указан"}</dd>
        </div>
        <div>
          <dt>Тариф</dt>
          <dd>наблюдаемый · цена наблюдалась {formatDateTime(leg.as_of)}</dd>
        </div>
      </dl>
      {leg.booking_url && (
        <a className="trip-plan__link" href={leg.booking_url} target="_blank" rel="noreferrer">
          Посмотреть этот рейс у поставщика ↗
        </a>
      )}
    </section>
  );
}

function CostRow({ component }: { component: PriceComponent }) {
  const isObserved = component.fulfilment === "estimate";
  const basis = isObserved ? OBSERVED_BASIS[component.kind] : MODELED_BASIS[component.kind];

  return (
    <tr>
      <th scope="row">
        <strong>{COMPONENT_LABELS[component.kind]}</strong>
        <small>{basis}</small>
      </th>
      <td>
        <span className={`basis basis--${component.fulfilment}`}>
          {isObserved ? "наблюдаемая оценка" : "моделируемая часть"}
        </span>
        <small>
          {component.source || "Источник не указан"}
          {observationNote(component)}
        </small>
      </td>
      <td className="trip-plan__amount-column">{formatMoney(component.amount)}</td>
    </tr>
  );
}

function observationNote(component: PriceComponent) {
  if (component.fulfilment === "estimate") {
    return component.as_of
      ? ` · наблюдение на ${formatDateTime(component.as_of)}`
      : " · времени наблюдения нет — цена не проверена";
  }
  return component.as_of ? ` · рассчитано на ${formatDateTime(component.as_of)}` : " · число не наблюдалось";
}

// The plan is marked outdated the moment it passes expires_at, including while it sits on screen (DEC-032).
function useOutdated(expiresAt: string) {
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const delay = Math.max(0, new Date(expiresAt).getTime() - Date.now());
    if (delay === 0) return undefined;

    const timer = window.setTimeout(() => setNow(Date.now()), delay);
    return () => window.clearTimeout(timer);
  }, [expiresAt]);

  return now >= new Date(expiresAt).getTime();
}

function originSplit(components: PriceComponent[], currency: string) {
  // Only add up numbers that are in the same currency; a mixed-currency sum would be a made-up number.
  if (!components.every((component) => component.amount.currency === currency)) return null;

  return components.reduce(
    (accumulator, component) => ({
      ...accumulator,
      observed: accumulator.observed + (component.fulfilment === "estimate" ? component.amount.amount_minor : 0),
      modeled: accumulator.modeled + (component.fulfilment === "modeled" ? component.amount.amount_minor : 0),
    }),
    { observed: 0, modeled: 0, currency },
  );
}

function nightsBetween(checkIn: string, checkOut: string) {
  const span = Date.parse(`${checkOut}T00:00:00Z`) - Date.parse(`${checkIn}T00:00:00Z`);
  if (Number.isNaN(span)) return 0;
  return Math.max(0, Math.round(span / MILLISECONDS_PER_DAY));
}

function nightsLabel(nights: number) {
  return `${nights} ${plural(nights, "ночь", "ночи", "ночей")}`;
}

function stopsLabel(stops: number) {
  if (stops === 0) return "без пересадок";
  return `${stops} ${plural(stops, "пересадка", "пересадки", "пересадок")}`;
}

function plural(count: number, one: string, few: string, many: string) {
  const lastTwo = count % 100;
  const last = count % 10;
  if (lastTwo >= 11 && lastTwo <= 14) return many;
  if (last === 1) return one;
  if (last >= 2 && last <= 4) return few;
  return many;
}

function formatMoney(money: { amount_minor: number; currency: string }) {
  return new Intl.NumberFormat("ru-RU", { style: "currency", currency: money.currency, maximumFractionDigits: 0 })
    .format(money.amount_minor / RUB_MINOR_UNITS_PER_MAJOR_UNIT);
}

function formatDate(date: string) {
  return new Intl.DateTimeFormat("ru-RU", { weekday: "short", day: "numeric", month: "long", year: "numeric" })
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

function formatDuration(minutes: number) {
  if (minutes < 60) return `${minutes} мин`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest === 0 ? `${hours} ч` : `${hours} ч ${rest} мин`;
}

function formatDistance(distance: number) {
  return distance < 1000 ? `${distance} м` : `${(distance / 1000).toFixed(1).replace(".", ",")} км`;
}

function seaDistance(distance: number | null) {
  if (distance === null) return "расстояние до моря неизвестно · источник не дал геометрию";
  return `${formatDistance(distance)} · геоданные Supply`;
}
