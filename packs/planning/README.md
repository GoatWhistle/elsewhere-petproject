# Planning — what we offer, and why

The product thesis in code. Every shortcut here is invisible and fatal — a model-produced score, a "diversity
objective" that is really top-3 by rank, a delta that rounds — and each one silently turns the product back into
a search results page.

## The division of labour with the model

**The model reads language and writes language. It never owns a number.** It is asked which dimensions a Dream
names, what level each asks for, and the *order* of importance; every weight, confidence and score is computed
here from fixed rules. Asking a model to rate importance 0–1 gives values that drift between runs; asking it to
rank gives something that turns into weights deterministically. The schemas it answers have no field for a
weight or a confidence, and specs assert that.

With no model configured every parse is degraded, and the fallback is a **lexicon over the user's own words**
rather than a guess at their meaning. What it finds is genuinely `stated`; what it cannot map goes to
`unmatched_intent` and is shown. The cost of losing the model is recall, and recall failures are displayed.

## Provenance, confidence and weight

| | |
|---|---|
| `stated` 1.0 | the user's own words |
| `inferred` 0.6 | worked out from something else they said (`car_free` → walkability, transfer) |
| `default` 0.3 | the taxonomy's, because nothing in the Dream could be scored |
| `confirmed` 1.0 | the user edited it; nothing inferred may overwrite it afterwards |

Weights come from position on a fixed ladder, and every stated dimension outranks every inferred one. A hard
constraint carries no weight at all — it disqualifies rather than competes.

## Hard constraints (B-3)

Only five may ever be hard: total budget, dates, trip length, party, `car_free`. Everything else is a
preference — the moment "quiet" can be hard, the result set is empty and nobody can say why.

**An inferred hard constraint is not enforced until confirmed.** `car_free` is inferred from a Dream about
walking everywhere, and enforcing that would disqualify destinations on the strength of something nobody said.

When nothing survives, the answer names the constraint doing the cutting and what the cheapest reachable option
actually costs. Never relax silently.

## Experience Match (B-4)

```
score      = Σ(wᵢ × sᵢ) / Σ(wᵢ)   over scored dimensions
coverage   = Σ(weights of scored) / Σ(all weights)
confidence = coverage × weighted mean of per-dimension confidence
```

Curves are **data** — one table of breakpoints with linear interpolation, so a breakpoint can be argued about in
a normal conversation. Normalization is against a fixed ideal, never against the candidate set: a moving
denominator would let 92% → 90% happen because the reference point shifted. Nothing scores 98%, and nothing is
rescaled for display.

The score is computed from the **published** contributions, not from unrounded intermediates — otherwise the
decomposition a user can add up differs from the score printed above it in the fourth decimal, and a
decomposition that cannot reproduce its own total is not a decomposition.

What cannot be measured says so: `crowds` needs seasonality and destination popularity, `nightlife` needs a bar
layer, and Supply publishes neither. They come back unscored with a reason and cost coverage. A destination with
no coastline, by contrast, scores `sea_access` **zero** — absent is not unmeasured.

## Diversity (B-5)

`A` best · `B` cheaper within 0.08 · `C` a different geography within 0.12. Archetypes rather than a spread
metric, because an archetype explains itself in one sentence and that sentence is already a required field.
**Never padded**: a homogeneous set returns two, and the note distinguishes "there was nothing else there" from
"what was there was not good enough".

## The Simulator (B-7)

The single mutation path for a Future. Sliders and natural language both map onto DEC-025's model changes;
weight and target changes re-solve over candidates already retrieved, and only dates or destinations go back to
Supply.

**ε = 0.05 is a refusal, not a fudge.** Asked to get cheaper, the system moves. Asked to get cheaper *without
damaging anything important*, it answers:

> дальше дешевеет только за счёт «sea_access» — потеря 1.0 при экономии 10 375 ₽. Не делаю это молча: решать вам.

A dragged slider is one version: the superseded intermediate is deleted rather than updated, so nothing is
mutated in place and the pixels are not kept.

## Deltas (B-8)

**Sequential re-pricing**, because attributing a joint change after the fact is order-dependent and the parts do
not sum. The order is fixed — dates, destination, property — the trip is re-priced after each step, and each
step's difference is one item. Items sum to the total change exactly, to the minor unit, by construction.

`new_risks` and `resolved_risks` are empty: Foresight reads Planning, not the other way round, so a Future
cannot ask it what appeared. The client fetches the forecast per version instead.

## Open ends

1. **The trip total's currency.** Ignav prices in USD, the room rate is modeled in RUB, and summing them needs
   an exchange rate whose provenance nobody has decided. Sochi — the one destination with a real observed fare —
   is therefore **refused** rather than invented, and `diversity_note` says so. This is the single biggest thing
   standing between the demo and three Futures.
2. **No transfer or local-mobility model exists in Supply**, so those price components are absent and the
   transfer note says neither its time nor its cost is modeled. B assembles; it does not invent.
3. **A leg's clock time is constructed.** Supply publishes a fare's duration but not its departure time, so
   `depart_at` is assembled at a fixed reference hour and `arrive_at` follows from the observed duration. It is
   the one constructed value in the trip, and the contract has no field to mark it as such — either Supply
   publishes segment times or the contract gains a label.
