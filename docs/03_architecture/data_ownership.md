# Владение данными

Одно правило: **у таблицы ровно один владеющий контекст, и только он её читает и пишет.**
Доступ к чужим данным идёт через интерфейсы из
[provider_adapters.md](../04_api/provider_adapters.md), никогда через SQL.

Именно это делает четыре направления работ непересекающимися на практике, а не на бумаге.

| Контекст | Таблицы |
|---|---|
| **Supply** | `destinations`, `properties`, `property_geo_features`, `destination_climate_normals`, `offer_snapshots`, `flight_price_snapshots`, `review_documents`, `provider_orders` |
| **Planning** | `planning_sessions`, `travel_dna_elements`, `clarifications`, `futures`, `future_versions`, `future_components`, `match_scores`, `match_contributions`, `deltas`, `delta_items` |
| **Foresight** | `forecasts`, `risk_items`, `risk_evidence`, `mitigations` |

## Ссылки между контекстами

Там, где контекст обязан указать на чужие данные, он хранит **только идентификатор** и разрешает его через
владеющий интерфейс:

- `forecasts.future_version_id` — Foresight хранит id и читает Future через `Planning::Futures.find`;
- `offer_snapshots.id` в `future_components` — Planning хранит id и читает через `Supply::Offers`.

Никаких внешних ключей через границу контекста и никаких соединений через неё. Цена — несколько лишних поисков;
выгода — двое могут менять свои схемы в один день, не согласовывая это друг с другом.

## Миграции

Каждый контекст владеет миграциями своих таблиц. Миграция, трогающая чужую таблицу, — нарушение границы, и её
следует отклонять на ревью так же, как packwerk отклоняет нарушение на уровне кода.
