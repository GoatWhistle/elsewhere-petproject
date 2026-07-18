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

## OSM extract into PostGIS (A-3)

**One command, repeatable:**

```sh
bin/rails runner 'puts Supply::Osm.import!(log: ->(l) { puts l })'
bin/rails runner 'puts Supply::Osm.import!(city_codes: %w[AER], layers: %w[road]).to_s'   # one slice
```

Re-running is safe and produces the same data: each `(city, layer)` is **replaced** as a unit, so a feature OSM
has since deleted disappears here too. Every Overpass answer is on disk before it is parsed, so a second run
sends nothing.

**Bounded by the properties we actually harvested**, never by a region. The bbox is the min/max of a city's own
property coordinates plus a per-layer margin — 4 km for POIs and roads, 25 km for the place node, 60 km for
aerodromes and coastline, because an airport is not inside a city bbox and a coastline is not a point.

| layer | selectors | `out` | what it is for |
|---|---|---|---|
| `place` | `node[place=city\|town]` | `body` | the real city centre — replaces A-1's property centroid |
| `aerodrome` | `nwr[aeroway=aerodrome]` | `center tags` | airport distance, transfer difficulty |
| `poi` | `nwr[amenity\|shop\|tourism\|leisure]` | `center tags` | POI and restaurant density |
| `road` | `way[highway=motorway\|trunk\|primary\|secondary]` | `geom tags` | road class and proximity, walkability |
| `coastline` | `way[natural=coastline]` | `geom tags` | sea distance, kept so ohsome's answer is checkable |

`out center` collapses a POI to a single coordinate. Density counts do not need a building outline, and asking
for one turns 13 MB into hundreds. Roads are the one layer fetched with real geometry, because "distance to the
nearest major road" is the entire question.

### Why Overpass, and why that is not "the OSM main API"

The rule is not to read from the **editing** API — whose own policy says it is *"not for read-only purposes or
projects"*. Overpass is the read service, and what we ask of it is what a regional extract would have given us:
one bbox per corpus city, filtered to five tag sets, fetched once, kept on disk. Geofabrik's smallest Russian
unit is a federal district — hundreds of megabytes of PBF, with no reader for it in this Gemfile — which is
exactly the whole-country time sink A-3 rules out.

Overpass runs **two slots per client** and answers `429` when both are busy, publishing when the next one frees.
The importer waits for it. That is the documented way to use the service, and it is a different thing from the
harvest, where a `429` comes from bot protection and means stop.

**Nothing here runs at request time.** A-4 precomputes from these tables; the API never waits on OSM.

## Geo features per property (A-4)

```sh
bin/rails runner 'puts Supply::GeoFeatures.compute!(log: ->(l) { puts l }).to_s'
bin/rails runner 'p Supply::Geo.features(property_id: "101hotels:5716")'
```

Precomputed, never per request. A generation scores 24 candidates; putting PostGIS on that path would make
every Future wait on geometry it could have known in advance. One query per city, not one per property — the
whole corpus takes about **six minutes** once, against 660 000 imported OSM features.

| field | how |
|---|---|
| `distance_to_sea_m` | nearest imported `coastline` way, on the ellipsoid |
| `distance_to_centre_m` | to the destination's OSM place node |
| `poi_count_500m`, `poi_per_km2`, `poi_density` | POIs within 500 m |
| `restaurant_count_500m` | the subset you eat in (`restaurant`, `cafe`, `bar`, `fast_food`, `pub`, `bakery`, …) |
| `walk_network_m_500m` | walkable metres inside 500 m, whole ways measured whole and only crossing ones clipped |
| `nearest_major_road_m`, `road_class` | nearest `motorway\|trunk\|primary\|secondary` way and its class |
| `airport_distance_m`, `airport_name` | nearest aerodrome, preferring one with an IATA code |
| `airport_transfer_min` | OpenRouteService driving matrix — **absent without a key** |

`poi_density` is `poi_per_km2 / (poi_per_km2 + 200)` — half-saturation, not a capped ratio. The capped version
was the first attempt and the real corpus killed it: against a 300/km² reference **148 of 408 properties pinned
at exactly 1.0**, so a quiet block of Kazan and the densest corner of Nevsky Prospekt scored the same. The curve
is monotone over the whole observed range (0 to 2 028 POI/km²) and the corpus now spreads 0.0 · 0.27 · **0.48**
· 0.67 · 0.91 across min, p25, median, p75, max.

K is **fixed**, never "the median of the current corpus": a denominator that moves as the corpus grows would
silently rescore every Future ever generated. `poi_per_km2` is published raw alongside it, so nobody has to
trust the curve.

**`unassessed` carries a reason per field.** "No coastline within this city's extract" and "we did not look"
are different facts and stay different; nothing here is filled in with a neutral value.

### The two shortcuts A-4 suggested, and what actually happened

**ohsome for coastline distance** — the public instance answers **403 on `/elements/geometry`** while
`/metadata` and `/elements/count` answer 200, so the endpoint that would have returned the geometry is not
available to us. It also turned out not to be needed: Overpass returns coastline ways as finished LINESTRINGs,
so there is nothing to "assemble by hand", and `ST_Distance` on the imported geometry is exact and costs no
network. ohsome is kept for what it can still do — an **independent check**:

```sh
bin/rails runner 'p Supply::GeoFeatures.verify_sea_distance("101hotels:5716")'
```

If the nearest coastline is D metres away, a square of half-width just under D/√2 must contain no coastline and
one of half-width 1.2·D must contain some. Two bounds, one independent source, no geometry endpoint required.

Run across the range, it agrees: **43 m**, **869 m** and **5 990 m** each give 0 coastline ways in the smaller
box and 1, 1 and 32 in the larger.

**OpenRouteService for walkability and transfer** — needs `ORS_API_KEY` in `.env`, which this build does not
have. The adapter is written and wired; without the key `airport_transfer_min` is `NULL` and `unassessed` says
`ORS_API_KEY is not set`. Walkability meanwhile has a local answer that does not need the key at all —
`walk_network_m_500m` from the imported walk network — so the only thing actually missing is drive time.

## Geo storage

`lat`/`lon` are plain numerics; PostGIS is reached through a **GIST expression index** on
`ST_SetSRID(ST_MakePoint(lon, lat), 4326)::geography`. A query that repeats that expression verbatim uses the
index. There is no geography column to keep in sync, and no postgis adapter gem to add.

`osm_features.geom` is a real `geometry(Geometry, 4326)` column with its own GIST index — there the geometry is
the data, not a derivative of two numerics. It has deliberately **no ActiveRecord model**: without the postgis
adapter gem a model would announce "unknown OID" on every boot, and nothing needs one — the import writes it in
bulk and A-4 reads it with PostGIS functions.
