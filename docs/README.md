# Документация Elsewhere

Этот каталог описывает действующий продукт и архитектуру. Историю обсуждений и промежуточные планы здесь не
храним: решение остаётся только тогда, когда помогает понять текущую систему.

## С чего начать

1. [Продукт](01_product/product.md) — для кого Elsewhere и какой результат он даёт.
2. [Механики](01_product/mechanics.md) — Travel DNA, Futures, Match, Simulator, Forecast и Trip Plan.
3. [Архитектура](03_architecture/architecture.md) — компоненты, потоки запросов и инварианты.
4. [Границы контекстов](03_architecture/bounded_contexts.md) — кто за что отвечает в коде.
5. [OpenAPI](04_api/openapi.yaml) и [внутренние интерфейсы](04_api/provider_adapters.md) — исполняемые контракты.

## Карта документов

### Проект

- [constraints.md](00_project/constraints.md) — внешние и продуктовые ограничения;
- [glossary.md](00_project/glossary.md) — единый словарь терминов;
- [decision_log.md](00_project/decision_log.md) — 32 принятых решения и причины.

### Продукт

- [product.md](01_product/product.md) — тезис, аудитория и пользовательский путь;
- [mechanics.md](01_product/mechanics.md) — точная семантика всех механик;
- [mvp_scope.md](01_product/mvp_scope.md) — что входит в MVP и что намеренно оставлено снаружи.

### Архитектура и данные

- [architecture.md](03_architecture/architecture.md) — форма системы и пути запросов;
- [bounded_contexts.md](03_architecture/bounded_contexts.md) — Packwerk-пакеты и правила зависимостей;
- [data.md](03_architecture/data.md) — источники, признаки, свежесть и владение таблицами;
- [ai_architecture.md](03_architecture/ai_architecture.md) — допустимая роль LLM и поведение при отказе.

### Контракты

- [openapi.yaml](04_api/openapi.yaml) — публичный HTTP API, источник правды по форме запросов и ответов;
- [provider_adapters.md](04_api/provider_adapters.md) — фасады Supply, Planning и Foresight.

### Исследования

- [research_log.md](02_research/research_log.md) — подтверждённые основания выбора источников и отвергнутые пути.

## Что является источником правды

| Вопрос | Источник |
|---|---|
| форма HTTP-запроса или ответа | `openapi.yaml` и conformance-тест |
| публичный интерфейс пакета | код фасада и `provider_adapters.md` |
| численный порог или компромисс | код, тест и соответствующий DEC |
| продуктовая семантика | `mechanics.md` |
| зависимость и владение данными | `package.yml`, миграции и `bounded_contexts.md` |

Если Markdown расходится с исполняемым контрактом или тестом, ошибочен Markdown. Исправление должно обновить
оба источника в одном изменении.

## Состояние

MVP реализован в одном Rails-приложении и React-интерфейсе. Fixture-режим автономен и покрыт сквозным тестом.
Live-режим зависит от действующих ключей внешних поставщиков; отсутствие ключа или данных отображается как
явная деградация, а не скрывается.
