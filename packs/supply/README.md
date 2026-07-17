# Supply — the outside world and the corpus

Everything in this system that makes a network call lives here (hard rule 3). Everything here answers in both
`live` and `fixture` mode, and every read says what it is: `freshness` (`live` / `cached` / `fixture`) and, for
money, `basis` (`observed` / `modeled`).

## The one door

`Supply::Http` is the only place that opens a socket. It never raises — a refusal, a timeout and a DNS failure
all come back as a `Response` with `error` set — and it enforces a per-host minimum interval itself, so no
adapter can forget to be polite.

## Harvest — the property catalogue (A-1)

One-time collection from 101hotels.com, chosen by DEC-016 and re-verified by the A-0 probe: the catalogue is
served in `schema.org` microdata on pages `robots.txt` leaves open, and a bounded pass is not refused.

```sh
bin/rails runner '
  cities = [
    { slug: "sochi",           city_code: "AER", name: "Сочи",             country: "Россия" },
    { slug: "sankt-peterburg", city_code: "LED", name: "Санкт-Петербург", country: "Россия" }
  ]
  puts Supply::Harvest.run(cities: cities, categories_per_city: 2, log: ->(l) { puts l }).to_s
'
```

**Re-running it costs nothing.** Every page fetched is written to `tmp/supply/harvest/<host>/<sha1>.html`
(override with `SUPPLY_HARVEST_CACHE`), and later passes parse from disk and send nothing — which is what makes
a parser fix cheap and keeps a "one-time collection" one-time. `refresh: true` is the deliberate exception.

What is bounded, and why:

| Bound | Value | Reason |
|---|---|---|
| interval between requests | 4 s per host | `robots.txt` sets `Crawl-delay: 8` for Bingbot only; nothing for us. Slower than a person clicking. |
| paths | `/main/cities/**` only | everything `robots.txt` disallows (`/search`, `/city*`, …) is refused by `Catalogue101.allowed?`, not merely avoided. |
| pages per city | `1 + categories_per_city` | the city page plus its own linked slices, read off the page rather than guessed. |
| photos | the 4 preview images on the listing | a property page carries ~375, and fetching one page per property would multiply the pass by 21×. |
| on refusal | the pass **stops** | C-04: no retry, no backoff-and-try-again, no varied request. A smaller corpus is the accepted outcome. |

Cities are an argument, not a constant: *which* cities make up the corpus is curation (A-2), not collection.

## What the harvest yields, and what it does not

Real, per property: name, coordinates, address, rating with its scale, review count, photos, and a **price
level** — `от 5 200 руб.`, stored as an integer in minor units.

That price is a **"from" teaser with no dates attached**. It is the only observed money in the room rate, and
everything seasonal built on top of it in A-7 is modeled. The source says so itself on a property page:
*"точную стоимость смотрите на сайте по датам"*.

`destinations.centre_source` says where a destination's centre came from. The harvest publishes no city centre,
so until A-3 imports the OSM place node it is `property_centroid` — the middle of what we collected, which is a
different claim and is labelled as one.

## Corpus — which destinations, and the proof it is not homogeneous (A-2)

Seven destinations, chosen from slugs the A-0 probe saw return a full listing, each with a real IATA code —
a destination we cannot price a flight to is not a destination.

| | destinations | why |
|---|---|---|
| **city** | LED · KZN · KGD | harvest most reliably and have the densest OSM data, so they carry the demo |
| **mountains** | MRV (Кисловодск) · NOZ (Шерегеш) | the contrast that makes a Future genuinely different |
| **sea** | AER (Сочи) · AAQ (Анапа) | two, so "warm sea" is not a single price point |

```sh
bin/rails db:seed                                             # rebuild from pages already on disk
bin/rails runner 'puts Supply::Corpus.seed!(offline: false, log: ->(l){puts l})'   # collect them first
bin/rails runner 'require "json"; puts JSON.pretty_generate(Supply::Corpus.coverage)'
```

**Every city is asked for the same slices** — its main listing plus `inexpensive` and `expensive`, both verified
present on all seven. An earlier pass took whichever categories came first alphabetically, which sampled 1–2
stars in one city and 4–5 in another; the "cheap/expensive axis" then measured the sampling rather than the
destinations. Comparability is the whole point of the number.

Which is why the price axis is read at **property** level: 403 observed price levels from 360 ₽ to 99 999 ₽,
p90/p10 ≈ **39×**, and **all seven** destinations offer options on both sides of the corpus median. Destination
medians converge (4 700–6 500 ₽) *by design* — a traveller choosing Kazan can still choose cheap or dear, and
comparing city medians would score that as "no spread" and be exactly wrong.

The popularity axis (55 → 772 reviews per property, **14×**) is catalogue review volume — the source
[experience_match.md](../../docs/01_product/experience_match.md) names for `crowds`. It is a popularity proxy,
and it says so in its own `basis` field. It is not a crowd measurement.

Geography is the one axis that is a **judgement**: nothing in the harvest says "this is a mountain town". It is
declared in `Corpus::MANIFEST` with the reason, rather than derived from a number that would only look objective.

`packs/supply/fixtures/corpus_profile.json` is the real corpus as it came out, so the spec asserts the real
spread without needing a harvested database. Regenerate it with
`bin/rails runner 'File.write("packs/supply/fixtures/corpus_profile.json", Supply::Corpus.snapshot)'`.

### Prices the source itself gets wrong

`properties.price_level_minor` is only set for a plausible nightly rate (300 ₽ – 500 000 ₽). Outside that band
it is `NULL` and `price_level_note` says why — the Sochi listing really does publish
*"от 1 400 000 000 руб. средняя цена за номер"*, and anchoring A-7's modeled rate on it would poison every price
built from it. Absence with a reason, never silent absence. Five of 408 properties have no observed base.

## Geo

`lat`/`lon` are plain numerics; PostGIS is reached through a **GIST expression index** on
`ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography`. A query that repeats that expression verbatim uses the
index. There is no geography column to keep in sync, and no postgis adapter gem to add.
