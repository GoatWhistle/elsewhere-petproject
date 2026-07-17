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

## Geo

`lat`/`lon` are plain numerics; PostGIS is reached through a **GIST expression index** on
`ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography`. A query that repeats that expression verbatim uses the
index. There is no geography column to keep in sync, and no postgis adapter gem to add.
