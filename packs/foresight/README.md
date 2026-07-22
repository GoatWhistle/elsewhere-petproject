# Foresight — what could go wrong, for this person

> ## Foresight is complete, on `pool-c-foresight`
>
> **C-1 … C-6** are done with `bin/check` green. Not merged into `main` — that is the lead's call.
> C-6 touches `packs/supply/` by design: [tasks.md](../../docs/05_delivery/tasks.md) assigns it to Foresight
> *jointly with A-7*, and it is the room-rate model's defensibility report.

Instead of a rating and a wall of reviews, this states the risks that matter **to this traveller**, each with the
measurement behind it. A review score answers "was this good on average?"; a forecast answers "what is likely to
go wrong *for you*?"

**Foresight describes; it never writes.** No Future, no future version, no call into `Planning::Simulator`. A
mitigation comes back as an adjustment payload and applying it is Planning's job — under deadline pressure
calling the Future-building code from here is the obvious shortcut, and it is how pricing and scoring logic ends
up existing in two places. A spec greps the pack for it.

## The ceiling, stated first

There is **no review source at all**, from anywhere, and C-05 says that is permanent rather than a gap waiting to
be filled. So `Supply::Reviews::Result(available: false)` is the *normal* path here — exercised on every single
forecast — and four of the nine risk types in the contract can only ever be evidenced by what people wrote:

| assessed from measurements | unassessable, every time, with the reason |
|---|---|
| `night_noise` · `walkability` · `weather_mismatch` · `transfer_difficulty` | `crowds` · `construction` · `weak_transport` · `room_location_mismatch` · `seasonal_closure` |

Coverage reports all nine on every response. Absence of evidence is reported as absence of evidence, never as
absence of risk.

## The four rules

Each names the number it read, the threshold it judged that number against, and which side of the line is risky.
A rule does **not** decide how bad something is — severity is derived from those three, so no rule can quietly
hand back a `high`.

| risk | measurement | threshold | claim |
|---|---|---|---|
| `night_noise` | distance to the nearest major road | by road class: 500 m trunk · 300 m primary · 150 m secondary · 100 m tertiary | `model_inference` |
| `walkability` | POI density within 500 m, restaurants | density 0.35, 5 restaurants | `derived_metric` |
| `weather_mismatch` | mean temperature over the stay's months | 20 °C warm · 24 °C cool | `derived_metric` |
| `transfer_difficulty` | airport distance, or ORS driving time | 40 km · 60 min | `derived_metric` |

**`night_noise` is a proxy and says so in its own statement.** We measured a distance to a road. We did not
measure noise, and nobody has told us which way the room faces. Presenting that with the authority of a
measurement is the fastest way to destroy the product's credibility, so the label never gets upgraded by how
confident the prose sounds.

Thresholds are Foresight's to set (OQ-D) and are thresholds, not measurements.

## Severity and confidence are separate axes (DEC-030)

**Severity** is three bands from how far past its threshold a measurement sits, as a fraction of that threshold —
relative, because the thresholds are in metres, degrees and densities. A primary road at 290 m is `low`, at
220 m `medium`, at 40 m `high`.

**Confidence** starts at the kind of claim — `verified_fact` 0.9 · `derived_metric` 0.75 · `model_inference` 0.5
— multiplied by how much of the data the rule actually had. Nothing raises it: an inference stays at 0.5 however
complete its inputs, because completeness is not proof. Those three numbers are the only confidence literals in
the pack, and a spec asserts it.

They must not be collapsed. A road 40 m away is high severity at 0.5 confidence; a neighbourhood barely under the
walkability line is low severity at 0.75. *"Probably fine but severe"* and *"certainly a minor annoyance"* demand
different things from a traveller.

## Relevance is part of the forecast

A forecast listing every possible risk is a wall of text. Risks are filtered to the dimensions this traveller
named — the product doc's own example is the test, and it passes: someone who came for nightlife is not warned
about street noise.

A preference needs real weight (≥ 0.5, since Planning assigns weights by rank). An aversion or a hard constraint
needs none — a thing you actively do not want matters however lightly it was said. When the DNA cannot be reached
at all, nothing is filtered: showing a risk somebody does not care about is a smaller failure than hiding one they
do.

Filtering changes which risks are *shown*. It never changes coverage.

## Mitigations are earned, not asserted

* the **adjustment** names the dimension the risk threatens, with a magnitude from the severity band;
* **severity_after** is recomputed by running the same rule against a real alternative in the corpus;
* **price_change** is the difference between two rates `Supply::Rates` actually quotes.

A noisy property is answered with a quieter one that exists; a cold month with a month whose normal clears the
threshold, priced on the shifted dates. **If nothing improves the band, no mitigation is offered** — a fix that
fixes nothing is noise.

Forecasts are computed on demand rather than stored. That is safe precisely because a Future is immutable: the
same id always yields the same forecast, so there is no cache to invalidate. It is also why the risk id carries
its future — the frozen interface `mitigation_adjustment(risk_id:, mitigation_id:)` passes no future along.
