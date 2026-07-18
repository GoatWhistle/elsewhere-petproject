# Журнал исследования

Проверенные находки с источниками. Всё здесь прочитано напрямую; непрочитанное помечено НЕИЗВЕСТНО.
Подробности об отвергнутых поставщиках сохранены ровно настолько, насколько объясняют *почему* их отвергли.

---

## 2026-07-17 — Можно ли собрать цены отелей со страниц? (решающее)

Три сайта проверены напрямую.

**101hotels.com**
- HTML отдаётся сервером, с микроразметкой: `itemprop` name / latitude / longitude / address / image, рейтинги,
  `data-price-value`, `data-price-currency`. Около 21 объекта на страницу каталога. **Каталог собирается чисто.**
- Цены **не реагируют на даты**: одинаковые цифры для 20–24 сентября и 20–24 декабря в Сочи, ответы различаются
  на 600 байт. Это «от», а не котировки на даты.
- Заголовок ответа `server: QRATOR` — впереди стоит защита от ботов.

**ostrovok.ru** — robots.txt запрещает `/hotels*` (поиск); страницы объектов разрешены, присутствует блок JSON.
**tvil.ru** — оболочка на 2 КБ, рисуется на клиенте.

**travel.yandex.ru** — robots.txt запрещает `/*/search*`, `/?*`, `*/book/*`, `*/booking/*`, `/api/`.
Запрещённое множество — ровно те данные, которые нужны; то, что остаётся обходимым, не несёт доступности на даты.

**Вывод.** Цены на даты везде сидят за XHR и защитой от ботов. Каталоги отдаются публично.
Отсюда и родилось [DEC-016](../00_project/decision_log.md): собрать каталог однажды, цену номера смоделировать.

---

## 2026-07-17 — Бесплатные и неограждённые данные, которые мы действительно используем

**Ignav** — flight fares. `POST /fares/one-way`, `POST /fares/round-trip`, flexible search, booking-link
generation, airport search. Auth `X-Api-Key`; free account, and *"try the playground — no signup required"*.
Base `https://ignav.com/api`. Pricing tiers and rate limits are not stated in the docs — UNKNOWN.
No hotel data of any kind. **Amended 2026-08-27 by the A-0 probe below: it returns no direct flight into or
out of Russia, so for this corpus the fare is modeled, not observed.** What survives is airport search and
the captured-fixture corpus.

**Open-Meteo** — климатические нормы и прогноз. Ключ не нужен. Ограничения бесплатного тарифа, цитата:
*«менее 10 000 вызовов API в день, 5 000 в час и 600 в минуту»*.
**Бесплатный тариф только некоммерческий** — коммерческим считается использование в приложениях с подписками или
рекламой либо встраивание в коммерческие продукты. Для этой сборки годится; станет платной зависимостью, если
продукт начнёт зарабатывать.

**OpenStreetMap** — географические признаки. Их политика API гласит, цитата: *«API редактирования предоставляется
для правки данных карты, **а не** для целей только чтения или проектов»*, и *«крупным или частым потребителям
данных следует использовать сервис загрузки planet.osm или другие альтернативы»*.
Отсюда: региональная выгрузка, однажды загруженная в PostGIS. Так и просто лучше — ни ключа, ни лимита, ни
задержки, ни сетевой зависимости во время демонстрации.

**ip-api.com** — опциональное предзаполнение города вылета. Без ключа, 45 запросов в минуту, но **HTTPS на
бесплатном тарифе нет** и *«мы не разрешаем коммерческое использование этого эндпоинта»*. Только со стороны
сервера, если использовать вообще.

---

## 2026-07-17 — Оценённые и отвергнутые поставщики

| Поставщик | Что предлагал | Почему отвергнут |
|---|---|---|
| **Yandex Travel Partner API** | поиск отелей, детали, **отзывы**, предложения, создание заказа, оплата на странице Яндекса, статус заказа | партнёрская модерация. Через Travelpayouts те же данные доступны **кроме `hotels/hotel/reviews`** — лёгкий путь убирает единственное, что делало Прогноз качественным |
| **Travelpayouts Data API** | цены на перелёты (`prices/cheap`, `calendar`, `month-matrix`, `city-directions`), кэшированные цены отелей, статические данные | живой поиск отелей *«требует отдельного одобрения доступа»*; цены кэшированные; бронирования нет |
| **Amadeus Self-Service** | мгновенный бесплатный ключ, предложения отелей и перелётов и **Hotel Ratings** — тональность отзывов по категориям (качество сна, расположение, сервис, еда). Тестовый тариф: *«ограниченный, кэшированный»*, 10 запросов в секунду, только крупные города | отвергнут: нероссийский |
| **RateHawk (Emerging Travel)** | настоящие остатки, песочница с четвёртого квартала 2025, доступ к API бесплатный | договор с отделом продаж |
| **Ostrovok B2B** | настоящие остатки | договор |
| **Bronevik** | около 80 тысяч объектов | заявка и NDA |
| **Kiwitaxi** (трансферы) | партнёрская программа через Travelpayouts | партнёрского API или white-label не нашлось |
| **Yandex Rasp** | междугородние расписания (самолёты, поезда, автобусы), без цен; атрибуция обязательна | не нужно для объёма, ограниченного логистикой |

Общая форма: реальные цены отелей на даты — договорные данные. Открытый ключ их не даёт.

## 2026-08-27 — A-0 probe 1: does Ignav cover our routes? (decisive — no, and worse than "domestic is empty")

Probed live with a real key against `https://ignav.com/api`. Health `{"ok":true}`; the account works; 14 requests spent.
Machine-readable spec at **`/api/openapi.json`** (`Ignav Public API 1.0.0`) — six endpoints: `GET /health`,
`GET /airports?q=&limit=`, `POST /fares/search` (1–2 ordered legs), `POST /fares/one-way`, `POST /fares/round-trip`,
`POST /fares/booking-links`. Auth header `X-Api-Key`.

**City codes are not accepted for fares.** `origin: "MOW"` →
`{"error":{"type":"invalid_request","code":"invalid_airport_code","message":"origin must be a supported 3-letter IATA code.","field":"origin"}}`
Airport *search* does resolve `q=MOW` → DME, SVO, VKO and `q=Sochi` → AER, so a city → airport expansion must happen
on our side, and a Moscow origin is **three** fare requests, not one, unless we pick one airport. Not stated in the
docs — found by probing.

### The three routes the task asked for, `2026-09-24`, one adult, economy

| Route | Itineraries | Cheapest | Reality |
|---|---|---|---|
| **SVO→AER** (domestic) | 2 | 46 523 ₽ Etihad, **17 h 15 m**, via **AUH** | nonstop 2 h 20 m, ~5–9 000 ₽, many daily |
| SVO→AER `max_stops:0` | **0** | — | — |
| DME→AER (domestic) | 7 | 22 489 ₽ FLYONE Armenia via **EVN**, 22 h; also 569 370 ₽ EgyptAir `DME>CAI>AMM>AUH>AER`, 48 h | as above |
| LED→AER (domestic) | 1 | 31 725 ₽ FLYONE Armenia via **EVN**, 8 h 20 m | nonstop ~2 h 30 m |
| **SVO→IST** (international from Moscow) | 9 | 40 601 ₽ Gulf Air via **BAH**, 16 h | Turkish flies it **nonstop**, ~3 h |
| **LHR→BCN** (control) | 9 | **52 £ Vueling, nonstop, 140 min**; BA 102–125 £ | correct |

Verbatim, the domestic answer:

```json
{"origin":"SVO","destination":"AER","departure_date":"2026-09-24",
 "itineraries":[{"price":{"amount":46523.0,"currency":"RUB","status":"verified"},
   "outbound":{"carrier":"Etihad Airways","duration_minutes":1035,
     "segments":[{"marketing_carrier_code":"EY","flight_number":"844","departure_airport":"SVO",
                  "arrival_airport":"AUH","duration_minutes":345,"aircraft":"Boeing 777"},
                 {"marketing_carrier_code":"EY","flight_number":"857","departure_airport":"AUH",
                  "arrival_airport":"AER","duration_minutes":245,"aircraft":"Airbus A320"}]},
   "ignav_id":"8525a9dcdd864f8da388bc8442d5094b"}, … ]}
```

**The gap is Russia, not "domestic".** One more probe settles which: **IST→AER** (foreign origin, Russian
destination) returns 8 itineraries and Turkish Airlines is among them — routed `IST>BEG>AER`, **23 h**, when
Turkish flies IST–AER nonstop in about two hours. So the underlying inventory returns **no direct flight into or
out of Russia, from any carrier, in any market**. Aeroflot, S7, Pobeda and Ural appear nowhere. What is left is a
residue of foreign-carrier connections priced 3× to 100× the real fare.

`"status":"verified"` on every one of them. The number is real; the itinerary is not one a traveller would take.
**A plausible-looking wrong number is worse than an empty result** — an empty result we would have shown as absent.

### Consequence

**[DEC-027](../00_project/decision_log.md) branch 2 fires, and wider than it was written.** DEC-027 anticipated
"Ignav returns no domestic fares". The measurement is stronger: for a Russian corpus reached from a Russian
origin, *every* route we serve is uncovered — domestic and international alike. So the fare is a **second modeled
number** for the whole product, not a domestic special case, and the honesty list becomes **two modeled numbers,
both named**: the room rate and the fare.

Ignav is still worth keeping wired, in three narrow roles, all of them real:
airport search (`q=Sochi` → AER, correct for Russian airports); the fixture corpus for `Supply::Flights`
(A-007 wants real captured responses and these are real); and the live path for any future non-Russian corpus,
where the control route proves it is accurate.

### Still UNKNOWN

Rate limits and remaining quota — **no** `X-RateLimit-*` or quota header on any response, and none documented.
The pricing page states 1 000 free requests then $2/1 000; nothing exposes the counter. `POST /fares/booking-links`
with `{"ignav_id": …}` returns itinerary plus `booking_options` (HTTP 200) — but it rejects `ignav_id` combined
with `market`/passenger fields (`conflicting_booking_lookup_mode`), so the two lookup modes are exclusive.

Raw captures (14 responses, headers included): `tmp/spike/ignav/` — gitignored, they become `Supply` fixtures in A-6.

---

## 2026-07-17 — Разведка: как далеко доходит сбор каталога, прежде чем его заблокируют? (не блокируют)

**Блокировки не было.** 25 запросов к 101hotels.com с интервалом 4 секунды, один честный опознавательный
User-Agent, без повторов, без ротации, без попыток тронуть то, что запрещает `robots.txt`. **Ноль ответов 429,
ноль проверок, никакой CAPTCHA.** Все ответы HTTP 200 за `server: QRATOR`, по 0,5–1,5 секунды. Неверные слаги
городов честно отвечали 404 (`/main/cities/arhyz`), и это единственный отказ, который мы видели.

**robots.txt, `User-agent: *`** — запрещены `/search`, `/city*`, `/redirect`, `/favorites`, `/nearby/location`,
`/?*`, `/booking/order_form`, `/app*`. **`/main/cities/**` не запрещён**, а это и есть весь каталог:
`/main/cities/<город>` перечисляет около 21 объекта, `/main/cities/<город>/<категория>` переразрезает тот же
город (`boutique_hotels`, `grand_hotel`, `hotel_stay` и так далее), `/main/cities/<город>/<слаг>.html` — один
объект. `Crawl-delay: 8` задан только для Bingbot; мы держали 4 секунды и остались далеко внутри.

### Что дал один ограниченный проход

**240 уникальных объектов в 14 населённых пунктах** из 25 запросов:

| | |
|---|---|
| sochi 48 · sankt-peterburg 21 · kazan 18 · kaliningrad 20 | **город** |
| dombai 21 · arkhyz 21 · krasnaya_polyana 21 · elbrus 20 · sheregesh 20 · kislovodsk 21 | **горы** |
| sochi · adler · lazarevskoe · loo · sirius | **тёплое море** |

- **координаты у 240 из 240** — `schema.org/GeoCoordinates`, `itemprop="latitude"/"longitude"`, полная точность;
- **рейтинг у 237 из 240** (`ratingValue` и `reviewCount`, например `9.4 / 10` по 1878 отзывам);
- **наблюдаемый ценовой уровень у 235 из 240** — `itemprop="priceRange"`, например
  `content="от 5 200 руб. средняя цена за номер"`, плюс `data-price-value="5200" data-price-currency="RUB"`;
- разброс: минимум 900 · p25 3 910 · **медиана 5 500** · p75 8 100 · максимум 130 000 ₽;
- устойчивый `data-hotel-id`, почтовый адрес, а на странице объекта **375 URL изображений** с `s.101hotelscdn.ru`.

Страница объекта несёт ту же микроразметку, что и список, только богаче. Обе отдаются сервером — никакого XHR, так
что этот сбор нигде не касается защиты от ботов.

### Следствие

**Допущение [A-012](../00_project/assumptions.md) держится там, где в нём сомневались, и только там.**
Наблюдаемый базовый уровень, нужный модели цены, существует для 98% корпуса, с настоящим разбросом: дёшево или
дорого — измеримая ось, а не догадка. **Запасной вариант через OSM `tourism=hotel` не нужен**, он остаётся на полке.

Двух вещей это **не** даёт, и формулировка важна:

- Цена по-прежнему `priceRange` — **завлекающее «от»**, одно число на объект, без дат. Одна страница объекта
  говорит об этом собственным текстом: `«…точную стоимость смотрите на сайте по датам»`. Это подтверждает
  находку выше: **наблюдаема только база, сезонность смоделирована**
  ([DEC-029](../00_project/decision_log.md)).
- Географическое покрытие — то, что дают городские страницы самого сайта. `/main/cities/arhyz` и
  `/main/cities/dombay` отвечают 404; рабочие слаги — `arkhyz` и `dombai`. Список корпуса (OQ-B) определяется
  тем, какие слаги разрешаются, и это теперь проверяется одним запросом на каждый.

Сырой HTML, по файлу на URL, плюс журнал запросов: `tmp/spike/harvest/` — в gitignore. Второй проход
перечитывает с диска и не делает ни одного запроса.

## 2026-07-18 — Что на самом деле разрешают географические поставщики

Записано, потому что ничего из этого нет ни в чьей документации.

**ohsome (`api.ohsome.org/v1`) — короткий путь к береговой линии недоступен.**
`/metadata` → 200. `/elements/count` → 200, отвечает на `natural=coastline and type:way` по bbox.
**`/elements/geometry` → 403 Forbidden** (Apache, не ошибка приложения), с опознавательным User-Agent и без него.
То есть эндпоинт, который вернул бы геометрию берега, для нас закрыт.

Он к тому же оказался не нужен. Ловушка, которую мы обходили — «собирать `natural=coastline` руками из
выгрузки», — не существует, когда выгрузка приходит из Overpass: он возвращает каждую линию готовым LINESTRING.
`ST_Distance` по импортированной геометрии точен, не стоит сети и выполняется на импорте.

`/elements/count` оставлен ради **независимой проверки** числа, на котором держится всё измерение доступа к морю:
если ближайший берег в D метрах, квадрат с полушириной чуть меньше D/√2 не должен содержать берега, а квадрат с
полушириной 1,2·D должен. Две границы, один внешний источник, без эндпоинта геометрии.

**Overpass (`overpass-api.de`) — два слота, и он сам об этом говорит.**
`/api/status` сообщает `Rate limit: 2` и печатает, когда освободится следующий слот. Оба неоднократно упирались во
время импорта из 34 запросов. Два разных сигнала занятости, и ни один не является отказом:
`429` (оба слота заняты — статусный эндпоинт сообщает время ожидания) и `504` с
`Dispatcher_Client::request_read_and_idx::timeout — the server is probably too busy`, что временно и проходит при
повторе через минуту. Ожидание — задокументированный способ пользоваться сервисом. Это **не** то же самое, что
429 при сборе каталога, который приходит от защиты от ботов и означает «стоп»; смешение этих двух случаев
заставило бы нас либо долбить общественный сервер, либо бросать импорт, который всего лишь стоял в очереди.

Размеры, измеренные, а не угаданные, для bbox центра Санкт-Петербурга: POI с `out center tags` —
**12,9 МБ и 43 642 элемента**; тот же запрос с полной геометрией на порядок больше и ни за чем, поскольку подсчёту
плотности не нужен контур здания. Крупные дороги с `out geom tags`: 2,5 МБ и 2 934 линии.

**OpenRouteService** — `ORS_API_KEY` в этой сборке не задан, поэтому пешая изохрона и время трансфера из
аэропорта НЕИЗВЕСТНЫ и так и сообщаются. Пешеходность от него не зависит: импортированная пешеходная сеть
отвечает на «сколько проходимых метров в пределах 500 м» локально. Ключ реально ограждает только время в пути от
аэропорта.

**PostGIS, для того, кто наткнётся следующим.** `ST_Intersection` возвращает `LINESTRING EMPTY` для короткой
линии, целиком лежащей *внутри* большого буфера, тогда как `ST_Within` на той же паре возвращает истину. Поэтому
обрезание линии по радиусу нельзя оставлять одному пересечению: содержащиеся целиком линии измеряются целиком, а
обрезаются только пересекающие.

---

## Sources

- https://travel.yandex.ru/robots.txt · https://ostrovok.ru/robots.txt · https://tvil.ru/robots.txt
- https://ignav.com/docs · https://ignav.com/api/openapi.json · https://ignav.com/pricing
- https://101hotels.com/robots.txt · https://101hotels.com/main/cities/sochi
- https://api.ohsome.org/v1/metadata · https://overpass-api.de/api/status · https://openrouteservice.org/dev/#/api-docs
- https://open-meteo.com/en/terms · https://operations.osmfoundation.org/policies/api/ · https://ip-api.com/docs/api:json
- https://yandex.ru/dev/travel-partners-api/ (+ `doc/ru/hotel-overview`, `doc/ru/booking-overview`)
- https://support.travelpayouts.com/hc/ru/articles/19677424987026 · https://travelpayouts-data-api.readthedocs.io/
- https://developers.amadeus.com/self-service · https://amadeus4dev.github.io/developer-guides/test-data/
- https://blog.ratehawk.com/introducing-the-ratehawk-api-sandbox/ · https://bronevik.com/en/partners
