# Источники данных

Решение: [DEC-016](../00_project/decision_log.md). Доказательства: [research_log](../02_research/research_log.md).

---

## Источник под каждую потребность

| Потребность | Источник | Шлюз | Стоимость | Настоящее? |
|---|---|---|---|---|
| Property catalogue — names, coordinates, addresses, photos, ratings, indicative price level | one-time harvest of public listing pages | none | free | real |
| POI/restaurant density, street network, road proximity | OSM regional extract → PostGIS | none | free | real |
| Coastline distance | **ohsome API** (`api.ohsome.org`) | **no key** | free | real |
| Walkability isochrones, airport transfer duration | **OpenRouteService** (`ORS_API_KEY`) | free account | free tier | real |
| Climate normals, forecast | Open-Meteo | none (no key) | free, **non-commercial tier** | real |
| Flight fares + booking links | Ignav | free account, 1000 free requests, no card | free tier | real, live — **coverage unverified, see A-0** |
| Origin city prefill | derived from the user's input; IP lookup optional | — | — | — |
| **Room price for given dates** | **modeled** — calibrated on harvested "from" levels + seasonality | none | free | **synthetic** |
| Hotel reviews | none | — | — | **absent** |

## Единственная синтетическая величина

Ровно одно число в продукте порождается: цена за ночь на конкретные даты. Всё остальное наблюдаемое.

Это честная форма сделки, на которую пошёл проект: любой путь к реальным ценам на даты закрыт партнёрским
договором, а продукту не нужна *покупаемая* цена, чтобы доказать свой тезис. Ему нужна правдоподобная и внутренне
согласованная, чтобы «сдвинь на два дня и сэкономь X» и «этот номер стоит тебе вида на море» были настоящим
рассуждением над согласованной моделью.

Правила, которые держат её честной:

- The modeled price is labeled `modeled` in `PriceComponent.fulfilment` and shown as such in the UI.
- It is calibrated on real observed price levels for the actual property, not invented per request.
- It is deterministic for a given property and date range, or the Simulator's deltas would be noise.
- We say it out loud in the demo.

## Чего стоит отсутствие отзывов

Нет ни текста отзывов, ни производной от них тональности. Прогноз работает только на географических и
климатических доказательствах: `weather_mismatch`, `walkability`, `night_noise` (заменитель через близость дороги,
помечен `model_inference`) и `transfer_difficulty`. Рейтинги из собранного каталога — слабый дополнительный сигнал.

Это четыре типа риска с доказательствами. MVP нужны два-три, сделанные честно.

## Две операционные заметки

**Бесплатный тариф Open-Meteo некоммерческий** — их условия определяют коммерческое использование как приложения
с подписками или рекламой либо встраивание в коммерческие продукты. Для этой сборки годится; станет платной
зависимостью, если продукт начнёт зарабатывать.

**Не читать из основного API OSM** — их политика прямо говорит, что он для редактирования, а не для проектов
только на чтение, и отправляет тяжёлых потребителей к выгрузкам. Мы однажды загружаем региональную выгрузку в
PostGIS. Так и просто лучше: ни ключа, ни лимита, ни задержки, ни сетевой зависимости во время демонстрации.

## География: три источника, намеренно

Выгрузка OSM отвечает на вопрос «что рядом с этим объектом» — плотность POI, рестораны, класс и близость дорог.
Она локальна, бесплатна и не ограничена, поэтому несёт основную нагрузку.

Две вещи она отвечает плохо, и обе делегированы:

- **Расстояние до береговой линии.** В OSM берег — это `natural=coastline`: незамкнутые линии, а не готовые
  полигоны. Собирать их руками — день геометрии ради самого важного признака в продукте («к морю»).
  **ohsome API** отдаёт геометрию напрямую и не требует ключа.
- **Пешая доступность и время трансфера.** «Дойти пешком» — это изохрона, а не радиус, а трансфер из аэропорта —
  длительность по маршруту, а не по прямой. **OpenRouteService** отвечает на оба. Его ключ лежит в `ORS_API_KEY`
  в `.env` и никогда не коммитится.

## Правила сбора каталога

- Разово, ради каталога. Не парсер во время работы и не ради цен.
- Никакого обхода защиты от ботов. `101hotels.com` стоит за QRATOR; сбор — ограниченный вежливый одноразовый
  проход, и если его блокируют, мы берём корпус поменьше, а не наращиваем давление.
- Собранные данные живут в нашей базе. Во время запроса с тех сайтов ничего не берётся.

## Соответствие признаков и измерений

| Измерение | Признак | Откуда |
|---|---|---|
| `sea_access` | расстояние от объекта до береговой линии | PostGIS и OSM |
| `walkability` | плотность POI, уличная сеть в радиусе | PostGIS и OSM |
| `food_quality` | плотность и разнообразие ресторанов и кафе в радиусе | PostGIS и OSM |
| `quiet` | класс и близость окрестных дорог | PostGIS и OSM |
| `climate_warm` | температурные нормы на кандидатные даты | Open-Meteo |
| `crowds` | заменитель через сезонность | Open-Meteo и рейтинги каталога |
| `comfort` | класс и рейтинг объекта, удобства | собранный каталог |
| `total_budget` | арифметика цены | модель цены и Ignav |
| `transfer_simplicity` | расстояние от аэропорта до объекта | PostGIS и OSM |

Измерения, которые нечем подтвердить, сообщаются через `ExperienceMatch.unscored_dimensions` — никогда не
оцениваются молча как нейтральные.
