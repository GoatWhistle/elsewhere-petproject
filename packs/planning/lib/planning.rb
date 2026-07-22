require "date"
require "time"
require_relative "../../shared/lib/elsewhere/values"
require_relative "elsewhere/store"
require_relative "../../shared/lib/ai/task"
require_relative "../../supply/lib/supply"
require_relative "planning/taxonomy"
require_relative "planning/lexicon"
require_relative "planning/clarifications"
require_relative "planning/dream_parser"

module Planning
  module_function

  def now; Time.now.utc.iso8601; end

  module Sessions
    module_function
    def now; Time.now.utc.iso8601; end
    def create(dream_text:, origin:, date_window:, party:)
      id = Elsewhere::Store.id
      dna = TravelDna.draft(dream_text, date_window, party)
      # Clarifications belong to the session, not the DNA: questions not yet asked, not beliefs about the user.
      session = { "id" => id, "created_at" => now, "dream_text" => dream_text, "travel_dna" => TravelDna.without_internals(dna),
                  "clarifications" => dna["_clarifications"] || [], "_origin" => origin,
                  "_date_window" => date_window, "_party" => party,
                  # Surfaced rather than acted on: a DNA the model never saw is not the same fact as one it did.
                  "_dna_degraded" => dna["_degraded"], "_dna_degraded_reason" => dna["_degraded_reason"] }
      Elsewhere::Store.save_session(session)
    end
    def find(id:); Elsewhere::Store.find_session(id); end
    def public(session); session.select { |key, _| %w[id created_at dream_text travel_dna clarifications].include?(key) }; end
  end

  module TravelDna
    module_function
    # Party is a fact about the trip and lives on the session, not a Travel DNA dimension.
    def draft(dream, date_window, _party)
      parsed = DreamParser.parse(dream)
      elements = parsed.elements.dup

      # Dates become a hard constraint; the party never becomes a dimension, and the contract spec asserts it.
      elements = elements.reject { |element| element["dimension"] == "dates" } +
                 [DreamParser.element("dates", date_window, "stated", DreamParser::NAMED)] if date_window

      { "id" => Elsewhere::Store.id, "version" => 1, "elements" => elements,
        "unmatched_intent" => parsed.unmatched_intent,
        "_clarifications" => parsed.clarifications, "_degraded" => parsed.degraded,
        "_degraded_reason" => parsed.degraded_reason }
    end

    INTERNAL_KEYS = %w[_clarifications _degraded _degraded_reason].freeze

    # Internal bookkeeping never crosses the serialization boundary; the conformance spec fails when it does.
    # Not named `public`: that is Module#public, and shadowing it makes the method private on the singleton.
    def without_internals(dna)
      dna.reject { |key, _| INTERNAL_KEYS.include?(key) }
         .merge("elements" => Array(dna["elements"]).map { |element| element.reject { |key, _| key.start_with?("_") } })
    end

    def update(session_id:, elements:)
      session = Sessions.find(id: session_id)
      previous = session["travel_dna"]
      # Editing preferences creates a new version; it never mutates one (DEC-023).
      dna = { "id" => Elsewhere::Store.id, "version" => previous["version"].to_i + 1, "elements" => elements.map { |e| e.merge("provenance" => e["provenance"] || "confirmed", "confidence" => 1.0) }, "unmatched_intent" => [] }
      session["travel_dna"] = dna
      Elsewhere::Store.save_session(session)
      dna
    end
    def answer_clarifications(session_id:, answers:)
      session = Sessions.find(id: session_id)
      session["clarifications"] = []
      Elsewhere::Store.save_session(session)
      session["travel_dna"]
    end
  end

  module Futures
    module_function
    def now; Time.now.utc.iso8601; end
    def generate(session_id:)
      session = Sessions.find(id: session_id)
      choices = [["AER", "prop-sochi-sea", "Море и еда", 9200000], ["AER", "prop-sochi-quiet", "Тишина и прогулки", 7900000], ["MRV", "prop-mrv-mountain", "Горы и спокойствие", 7200000]]
      futures = choices.map.with_index { |choice, index| build(session, choice, index) }
      futures.each { |future| Elsewhere::Store.save_future(future) }
      { "kind" => "futures", "futures" => futures.map { |future| public(future) } }
    end
    def list(session_id:); Elsewhere::Store.futures_for_session(session_id); end
    def find(future_id:); Elsewhere::Store.find_future(future_id); end

    # `session_id` indexes a Future in the store and is not in the contract, so it is stripped at the
    # serialization boundary; the conformance spec fails when it leaks.
    INTERNAL_KEYS = %w[session_id].freeze
    def public(future); future && future.reject { |key, _| INTERNAL_KEYS.include?(key) }; end

    def build(session, choice, index, parent: nil, version: 1)
      city, property_id, why, flight_amount = choice
      property = Supply::Catalog.property(id: property_id)
      nights = 7
      rate = Supply::Rates.for(property_id: property_id, check_in: "2026-07-08", check_out: "2026-07-15", adults: 2)
      transfer = city == "MRV" ? 35000 : 45000
      mobility = city == "MRV" ? 50000 : 25000
      accommodation_amount = rate["amount"]["amount_minor"]
      total = flight_amount + accommodation_amount + transfer + mobility
      match = [0.94, 0.91, 0.87][index] || 0.86
      id = Elsewhere::Store.id
      { "id" => id, "session_id" => session["id"], "lineage_id" => parent ? parent["lineage_id"] : id, "version" => version, "travel_dna_version_id" => session["travel_dna"]["id"], "parent_id" => parent && parent["id"], "created_at" => now, "expires_at" => (Time.now + 3600).utc.iso8601, "destination" => destination(city), "check_in" => "2026-07-08", "check_out" => "2026-07-15", "accommodation" => accommodation(property, rate), "logistics" => logistics(session.fetch("_origin"), city, flight_amount), "price" => price(total, flight_amount, accommodation_amount, transfer, mobility), "match" => match(match, session["travel_dna"]), "why_this_exists" => why, "benefits" => [why], "compromises" => index == 0 ? ["Больше людей в сезон"] : ["Часть поездок потребует транспорта"], "delta" => nil, "forecast_summary" => [] }
    end
    def destination(city); d = Supply::Catalog.destination(city_code: city); { "city_code" => d.city_code, "name" => d.name, "country" => d.country, "coordinates" => d.coordinates }; end
    def accommodation(property, rate); { "catalogue_id" => property.catalogue_id, "name" => property.name, "room_name" => "Стандартный номер", "handoff_url" => rate["handoff_url"], "coordinates" => property.coordinates, "cancellation" => { "refundable" => true, "free_until" => nil, "summary" => "Бесплатная отмена до заезда" }, "distance_to_sea_m" => Supply::Geo.features(property_id: property.catalogue_id)["distance_to_sea_m"], "distance_to_centre_m" => Supply::Geo.features(property_id: property.catalogue_id)["distance_to_centre_m"] }; end
    def logistics(origin, city, amount); { "outbound" => leg(origin, city, amount), "inbound" => leg(city, origin, amount), "airport_transfer" => { "mode" => "shared", "duration_min" => 35, "note" => "Моделируем shared transfer" }, "local_mobility" => { "assumption" => "Основное — пешком, две поездки на такси", "walkable" => true } }; end
    def leg(origin, destination, amount); { "origin" => origin, "destination" => destination, "depart_at" => "2026-07-08T09:00:00Z", "arrive_at" => "2026-07-08T12:00:00Z", "carrier" => "Fixture Air", "stops" => 0, "duration_min" => 180, "as_of" => now, "booking_url" => "https://example.invalid/flights" }; end
    def price(total, flight, accommodation, transfer, mobility); { "total" => { "amount_minor" => total, "currency" => "RUB" }, "components" => [{ "kind" => "travel", "amount" => { "amount_minor" => flight, "currency" => "RUB" }, "fulfilment" => "estimate", "source" => "Ignav fixture", "handoff_url" => "https://example.invalid/flights", "as_of" => now }, { "kind" => "accommodation", "amount" => { "amount_minor" => accommodation, "currency" => "RUB" }, "fulfilment" => "modeled", "source" => "harvest calibration", "handoff_url" => nil, "as_of" => nil }, { "kind" => "transfer", "amount" => { "amount_minor" => transfer, "currency" => "RUB" }, "fulfilment" => "modeled", "source" => "shared transfer model", "handoff_url" => nil, "as_of" => nil }, { "kind" => "local_mobility", "amount" => { "amount_minor" => mobility, "currency" => "RUB" }, "fulfilment" => "modeled", "source" => "mobility assumption", "handoff_url" => nil, "as_of" => nil }] }; end
    def match(score, dna); { "score" => score, "coverage" => 0.85, "confidence" => 0.82, "contributions" => dna["elements"].select { |e| e["weight"] }.map { |e| { "dimension" => e["dimension"], "satisfaction" => score, "weight" => e["weight"], "contribution" => (score * e["weight"]).round(4), "confidence" => e["confidence"], "explanation" => "Рассчитано по данным fixture" } }, "unscored_dimensions" => [{ "dimension" => "food_quality", "reason" => "Нет отзывов в текущем источнике" }] }; end
  end

  module Simulator
    module_function
    def simulate(future_id:, adjustments: nil, instruction: nil, persist_to_dna: false)
      original = Futures.find(future_id: future_id)
      raise "Future not found" unless original
      changed = Marshal.load(Marshal.dump(original))
      changed["id"] = Elsewhere::Store.id
      changed["version"] = original["version"] + 1
      changed["parent_id"] = original["id"]
      changed["lineage_id"] = original["lineage_id"]
      changed["price"]["total"]["amount_minor"] -= 830_000
      changed["match"]["score"] = (changed["match"]["score"] - 0.02).round(2)
      changed["delta"] = { "from_future_id" => original["id"], "price_before" => original["price"]["total"], "price_after" => changed["price"]["total"], "price_change" => { "amount_minor" => -830000, "currency" => "RUB" }, "items" => [{ "description" => "Отель дальше от моря → экономия на локации", "amount" => { "amount_minor" => -830000, "currency" => "RUB" }, "relaxed_dimension" => "sea_access" }], "match_before" => original["match"]["score"], "match_after" => changed["match"]["score"], "dimension_changes" => [{ "dimension" => "sea_access", "change" => "worsened" }], "new_risks" => [], "resolved_risks" => [], "explanation" => "Снижена цена за счёт наименее важного компромисса." }
      Elsewhere::Store.save_future(changed)
      { "kind" => "future", "future" => Futures.public(changed) }
    end
  end
end
