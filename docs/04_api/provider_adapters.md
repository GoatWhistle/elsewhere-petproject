# Внутренние интерфейсы (Supply и фасады контекстов)

Это **вторая заморозка контракта** (DEC-008, DEC-010). Как только эти сигнатуры существуют, четыре направления
работ идут, не трогая код друг друга.

Сигнатуры на Ruby ниже и есть контракт. Типы в `[скобках]` — значимые объекты, а не модели ActiveRecord:
пересечение границы с записью является нарушением границы.

---

## Supply — единственный код, говорящий наружу

```ruby
module Supply
  # ---- Направления и объекты -------------------------------------------------

  # Курируемый корпус (DEC-012). Никогда не живой вызов поставщика.
  Catalog.destinations(axes: nil)                 # => [Destination]
  Catalog.destination(city_code:)                 # => Destination
  Catalog.properties(city_code:, limit:)          # => [Property]

  # ---- Цены номеров (МОДЕЛЬ — единственная синтетическая величина, DEC-016) ---

  # Детерминирована для данного объекта и диапазона дат, иначе дельты Симулятора превращаются в шум.
  # Откалибрована на ценовых уровнях, наблюдавшихся при сборе каталога, плюс сезонность.
  Rates.for(property_id:, check_in:, check_out:, adults:)
    # => Rate(amount: Money, basis: :modeled, calibration: CalibrationRef, handoff_url: URI)

  # ---- Перелёты (настоящие, живые — Ignav) -----------------------------------

  # Настоящий наблюдаемый тариф, который мы не можем продать. `as_of` обязателен.
  Flights.price(origin:, destination:, depart_on:, return_on:, adults:)
    # => FlightFare(amount: Money, as_of: Time, carrier:, duration:, booking_url: URI)

  # Движок за фразой «сдвинь даты и сэкономь X».
  Flights.around_dates(origin:, destination:, depart_on:, window_days:)
    # => [DayPrice(date:, amount: Money, as_of:)]

  # ---- География (локальный PostGIS поверх выгрузки OSM; сети нет) ------------

  Geo.features(property_id:)
    # => GeoFeatures(distance_to_sea_m:, distance_to_centre_m:, poi_density:,
    #                restaurant_count_500m:, nearest_major_road_m:, road_class:,
    #                walk_score_components:, airport_distance_m:)

  Geo.features_for_destination(city_code:)  # => DestinationGeoFeatures

  # ---- Климат ----------------------------------------------------------------

  Climate.normals(city_code:, month:)      # => ClimateNormals(temp_mean_c:, rain_days:, sea_temp_c:)
  Climate.forecast(city_code:, from:, to:) # => [DailyWeather]

  # ---- Отзывы ----------------------------------------------------------------

  # Источника не существует (DEC-016). Оставлено в интерфейсе, чтобы деградированный путь Foresight
  # прогонялся с первого дня и чтобы будущий поставщик встал на место, не трогая вызывающих.
  Reviews.for_property(property_id:, since: nil)
    # => Reviews::Result(documents: [], available: false, reason: "no review source")
end

# Модуля заказов нет. Elsewhere не создаёт заказов (DEC-017).
```

### Три правила

1. **Каждое чтение объявляет свою природу** — `freshness` (`:live`, `:cached`, `:fixture`), а для цен ещё и
   `basis` (`:observed`, `:modeled`). Никому дальше по цепочке не приходится гадать, настоящее ли перед ним число.
2. **Недоступность — это значение, а не исключение.** `Reviews::Result(available: false, reason:)` — обычный
   возврат. Foresight снижает покрытие, ничто не падает. Ошибки поставщика за пределы этого модуля не выходят.
3. **Две реализации за одним интерфейсом** (DEC-005), выбор по конфигурации:
   `Supply::Adapters::Live` и `Supply::Adapters::Fixture`. Фикстуры строятся из **реально захваченных ответов**
   (A-007) — выдуманные формы ответов сделали бы границу фикцией.

---

## Planning

```ruby
module Planning
  Sessions.create(dream_text:, origin:, date_window:, party:)  # => Session (с черновиком TravelDna)
  Sessions.find(id:)                                           # => Session
  TravelDna.update(session_id:, elements:)                     # => TravelDna
  TravelDna.answer_clarifications(session_id:, answers:)       # => TravelDna

  Futures.generate(session_id:)          # => Job  (асинхронно — обращения к поставщикам)
  Futures.list(session_id:)              # => FutureSet(futures: [Future], diversity_note: String | nil)
  Futures.find(future_id:)               # => Future

  # Единственная точка входа для ЛЮБОГО изменения Future — ползунки, естественный язык
  # и применённые смягчения идут через неё.
  Simulator.simulate(future_id:, adjustments: nil, instruction: nil, persist_to_dna: false)
    # => Job => Future (новая версия, с .delta) | NoSolution
end
```

То, что `Simulator.simulate` — единственный путь изменения, и не даёт Foresight обзавестись собственными копиями
логики цены и оценки.

---

## Foresight

```ruby
module Foresight
  Forecasts.for_future(future_id:)   # => Forecast(risks: [RiskItem], coverage: [Coverage])

  # Возвращает полезную нагрузку корректировки. Применяет её Planning::Simulator, но не Foresight.
  Forecasts.mitigation_adjustment(risk_id:, mitigation_id:)
    # => Adjustment | OfferSwap(offer_id:)
end
```

---

---
## Доменные события

Публикуются внутри процесса (Rails, без брокера — объём событий его не оправдывает). Список подписчиков и есть вся
площадь интеграции между контекстами, поэтому он намеренно короткий.

| Событие | Публикует | Потребляет |
|---|---|---|
| `future.version_created` | Planning | Foresight (сбросить кэш прогноза) |

---

## Чего не должно случиться ни при каких обстоятельствах

Любое из этого — нарушение границы:

- HTTP-вызов к поставщику вне `Supply`;
- контекст, запрашивающий чужую таблицу;
- Foresight, пишущий `future_version`;
- арифметика цен где-либо, кроме Planning и Supply;
- модель ActiveRecord, пересекающая границу модуля.
