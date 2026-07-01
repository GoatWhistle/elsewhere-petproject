# Elsewhere — база знаний проекта

Этот каталог — источник правды по проекту. Переписка и обсуждения им не являются.
Новый человек должен начать отсюда и восстановить полную картину.

---

## Что такое Elsewhere

Elsewhere заменяет привычный путь

`Направление → Даты → Фильтры → Сотни отелей → Отзывы → Бронирование`

на

`Мечта → Futures → Симуляция → Прогноз → План`

Пользователь описывает поездку, которую хочет прожить («тепло, у моря, на неделю, примерно €1800, спокойно,
вкусно есть, много ходить пешком»). Система собирает небольшой набор намеренно разных вариантов — **Futures**, —
объясняет их компромиссы, даёт подвинуть параметры до того, как что-то решено, показывает риски с
доказательствами и выдаёт целую поездку: перелёт, проживание, трансферы, общую стоимость.

Полная формулировка: [product_thesis.md](01_product/product_thesis.md)

---

## Состояние

Оба контракта заморожены: публичный API ([openapi.yaml](04_api/openapi.yaml)) и внутренние интерфейсы
([provider_adapters.md](04_api/provider_adapters.md)). Работа разделена на четыре непересекающихся направления
по границам пакетов: Supply, движок решений, Foresight и фронтенд.

---

## Что читать первым

0. **Собираешься писать код?** → [bounded_contexts.md](03_architecture/bounded_contexts.md) — кто чем владеет,
   затем два контракта: [openapi.yaml](04_api/openapi.yaml) и
   [provider_adapters.md](04_api/provider_adapters.md).
1. [product_thesis.md](01_product/product_thesis.md) — что мы строим и зачем
2. [core_mechanics.md](01_product/core_mechanics.md) — шесть механик и как они связаны
3. [open_questions.md](06_questions/open_questions.md) — что не решено
4. [assumptions.md](00_project/assumptions.md) — во что мы верим без подтверждения
5. [constraints.md](00_project/constraints.md) — технические и правовые границы
6. [glossary.md](00_project/glossary.md) — точное значение каждого термина
7. [decision_log.md](00_project/decision_log.md) — принятые решения

---

## Что уже решено

- **Данные:** поставщика отелей нет — любой путь к реальным ценам на даты закрыт договором или модерацией.
  Настоящий каталог объектов **собран разово**; география — из **выгрузки OSM в PostGIS**, климат — из
  **Open-Meteo**, авиатарифы — живые из **Ignav**. **Ровно одно число синтетическое — цена номера**, построенная
  на наблюдаемых ценовых уровнях. Доказательства и отвергнутые варианты:
  [research_log](02_research/research_log.md).
- **Результат:** **план поездки** — логистика и стоимость, ничего не забронировано, денег нет (DEC-018).
  Программа по дням вне объёма, Living Trip тоже (DEC-015).
- **Объём:** Future = перелёт туда-обратно + реальный объект размещения + трансфер + локальная мобильность,
  с общей оценкой стоимости.
- **Доказательства для Прогноза:** только география и климат — источника отзывов не существует. Четыре типа
  риска обеспечены доказательствами.
- **Рынок:** Россия. Набор направлений определяется тем, что покрыл собранный корпус.
- **Контракт:** публичный API заморожен как [OpenAPI 3.1](04_api/openapi.yaml) — 10 путей, 33 схемы.
- **Команда:** несколько параллельных исполнителей, жёсткого дедлайна нет. Ограничение — интеграция, а не часы.

## Что открыто сейчас

**Блокеров нет.** Две вещи требуют ответа:

| Что | Кто отвечает |
|---|---|
| Какие направления реально покрывает сбор каталога | Supply, первая задача |
| Как калибруется модель цены номера и остаётся детерминированной | Supply + Foresight |

---

## Последние решения

| ID | Решение | Статус |
|---|---|---|
| DEC-018 | Результат — план поездки (логистика и стоимость), ничего не бронируется | Принято |
| DEC-017 | Бронирование становится передачей пользователя дальше: ни заказов, ни платежей | Заменено DEC-018 |
| DEC-016 | Собранный каталог + бесплатная география и климат + живые тарифы + модельные цены номеров | Принято |
| DEC-015 | Living Trip вне объёма | Принято |
| DEC-014 | Четыре параллельных направления работ с исключительным владением файлами и таблицами | Принято |
| DEC-013 | Пять ограниченных контекстов в одном Rails-монолите (packwerk); фронтенд на React и TS | Принято |
| DEC-012 | Корпус направлений выводится из данных о перелётах | **Заменено DEC-016** |
| DEC-011 | Доказательства для Прогноза многоисточниковые; отзывы — улучшение, а не зависимость | Принято |
| DEC-010 | Публичный API заморожен как OpenAPI 3.1 (`04_api/openapi.yaml`) | Принято |
| DEC-009 | Цены на перелёты из Travelpayouts Data API; трансферы моделируются | **Заменено DEC-016** |
| DEC-008 | Параллельные исполнители: контракты интерфейсов замораживаются до реализации | Принято |
| DEC-007 | Рынок — поездки с вылетом из России, цены в рублях | Принято |
| DEC-006 | Elsewhere не работает с деньгами | Принято (усилено DEC-017) |
| DEC-005 | Один интерфейс поставщика, две реализации: живой API и фикстуры | Принято |
| DEC-004 | Мы не парсим travel.yandex.ru | Принято |
| DEC-003 | Поставщик — Yandex Travel Partner API | **Заменено DEC-016** |
| DEC-002 | Модульный монолит на Rails и PostgreSQL | Принято (предварительно) |
| DEC-001 | База знаний в Markdown — это память проекта | Принято |

Полный журнал: [decision_log.md](00_project/decision_log.md)

---

## Карта документов

**Продукт** — [product_thesis](01_product/product_thesis.md) · [user_problem](01_product/user_problem.md) ·
[target_users](01_product/target_users.md) · [user_journey](01_product/user_journey.md) ·
[core_mechanics](01_product/core_mechanics.md) · [travel_dna](01_product/travel_dna.md) ·
[futures](01_product/futures.md) · [future_simulator](01_product/future_simulator.md) ·
[experience_match](01_product/experience_match.md) · [experience_forecast](01_product/experience_forecast.md) ·
[trip_plan](01_product/trip_plan.md) · [mvp_scope](01_product/mvp_scope.md)

**Проект** — [project_overview](00_project/project_overview.md) · [glossary](00_project/glossary.md) ·
[assumptions](00_project/assumptions.md) · [constraints](00_project/constraints.md) ·
[decision_log](00_project/decision_log.md)

**Исследование** — [research_log](02_research/research_log.md) (проверенные находки, отвергнутые поставщики,
источники) · [hotel_inventory_providers](02_research/hotel_inventory_providers.md) (почему поставщика нет)

**Домен и архитектура** — [bounded_contexts](03_architecture/bounded_contexts.md) ·
[architecture_overview](03_architecture/architecture_overview.md) ·
[architecture_principles](03_architecture/architecture_principles.md) ·
[c4_container](03_architecture/c4_container.md) · [ai_architecture](03_architecture/ai_architecture.md)

**Данные** — [data_sources](03_architecture/data_sources.md) · [data_ownership](03_architecture/data_ownership.md)
---

**Контракты** — [openapi.yaml](04_api/openapi.yaml) · [provider_adapters](04_api/provider_adapters.md)
(внутренние интерфейсы) · [api_principles](04_api/api_principles.md) · [public_api](04_api/public_api.md)

**Вопросы** — [open_questions](06_questions/open_questions.md)

---

## Где находится сборка

Сначала последовательно легло основание: скелет Rails с packwerk и PostGIS, общие значимые объекты, интерфейс
`Supply` с фикстурным адаптером, `AI::Task` и сгенерированный TS-клиент с MSW. Затем сбор каталога и выгрузка
OSM превратили корпус из идеи в данные.

Четыре направления шли после этого и не разговаривали друг с другом иначе как через контракты: Supply, движок
решений, Foresight и фронтенд. Все они в `main`, набор тестов зелёный.

Осталась не сборка, а проверка: модель не измеряли на наборе персон, а единственный прогон в режиме
`SUPPLY_MODE=live` не прошёл — Ignav ответил отказом в аутентификации.
