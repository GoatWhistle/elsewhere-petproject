# Объём MVP

---

## На какой вопрос отвечает документ

> Какая самая маленькая система доказывает основной тезис?

При известном профиле ограничений — несколько параллельных исполнителей, жёсткого дедлайна нет, один поставщик
данных, платежей нет — «самая маленькая» означает не столько часы, сколько **площадь интеграции**. Объём ниже
устроен так, чтобы настоящая интеграция была одна, а всё остальное распараллеливалось.

## Тезис, который доказываем

1. пользователь описывает желаемый опыт;
2. система строит структурированную Travel DNA;
3. система возвращает несколько осмысленно разных Futures;
4. пользователь меняет желаемое будущее;
5. система пересчитывает и объясняет компромиссы;
6. система показывает риски с доказательствами;
7. пользователь получает целую поездку — перелёт, проживание, трансфер, мобильность, общую стоимость — с
   указанием происхождения каждого числа.

Демонстрировать транзакцию не нужно ([DEC-018](../00_project/decision_log.md)). Все усилия уходят в механики, а
демонстрация прямо называет единственное модельное число.

## Предлагаемый объём

| Возможность | Уровень | Замечания |
|---|---|---|
| Dream input (free text + minimal structured fields) | REAL | Origin and dates are unavoidable inputs — OQ-I |
| Travel DNA extraction | REAL | Thesis 2 — cannot be faked |
| Travel DNA visible and editable | REAL | Cheap, and it is the product's honesty made visible |
| Futures generation with explicit diversity | REAL | Thesis 3 — hardest and most important |
| Experience Match, deterministic + decomposable | REAL | Thesis 5 needs it diffable |
| Simulator: 3 sliders + free-text request | REAL | Thesis 4–5 |
| Explained deltas | REAL | The most differentiating output in the product |
| Experience Forecast, 2–3 risk types with real evidence | REAL (narrow) | Geo and climate evidence only — C-05 |
| Property catalogue (real properties, coordinates, ratings) | REAL — harvested once | DEC-016 |
| Room price for dates | **MODELED** — calibrated on observed levels | DEC-016; the only synthetic number |
| Flight fare | REAL, live | Ignav |
| Geo features, climate | REAL | OSM/PostGIS, Open-Meteo |
| Trip plan (logistics + estimated total) | REAL | DEC-018 — nothing booked, no money |
| Day-by-day programme (sights, food, routes) | OUT | Different mechanic; would dilute the one that matters |
| Payment | OUT — we never touch money | DEC-017 |
| Reviews / review sentiment | OUT — no source exists | DEC-016 |
| Transfer + local mobility | MODELED, stated as assumptions | DEC-018 |
| User accounts | OUT | Nothing to return to — there is no order (DEC-017) |
| Multi-currency | OUT — RUB only | DEC-007 |
| Families / groups / accessibility | OUT | See [target_users.md](target_users.md) |
| Sharing a Future with a companion | OUT (POST-MVP) | Obvious next step, not thesis-critical |
| Living Trip (post-booking monitoring) | **OUT** — [DEC-015](../00_project/decision_log.md) | Lead's decision |

Note the one item that moved *into* scope: minimal identity. It was not required when booking was hypothetical;
it becomes required the moment a user leaves for a payment page and needs to come back to their order.

## Sequencing for five parallel builders

Serial first (nobody can parallelise around these):

1. Supply interface plus the harvested corpus and the price model (DEC-016).
2. The core schemas: Travel DNA, Future, scoring input/output, forecast item (DEC-008).
3. The destination set the corpus actually covers.

Then, in parallel:

- Dream parsing → Travel DNA
- Futures generation + diversity + Experience Match
- Simulator + delta explanation
- Forecast (evidence extraction → risk items)

- Front end

The demo scenario should be written early, not last — it is the acceptance test for all of the above.

## What must be REAL for the demo to mean anything

If these are faked, the demo proves nothing:

- Travel DNA extraction from free text;
- Futures diversity;
- Experience Match decomposition;
- the simulator's delta arithmetic;
- the forecast's evidence chain — a risk must trace to a real review with a real date.

Inventory and booking may run against the seeded adapter without damaging the thesis, **provided we say so**.

## Still open

Which destinations the harvested corpus covers, and how the room-rate model is calibrated.
