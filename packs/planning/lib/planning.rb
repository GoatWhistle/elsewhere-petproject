require "date"
require "time"
require_relative "../../../app/values"
require_relative "../../../app/elsewhere/store"
require_relative "../../../app/ai/task"
require_relative "../../supply/lib/supply"

module Planning
  module_function

  def now; Time.now.utc.iso8601; end

  module Sessions
    module_function
    def create(dream_text:, origin:, date_window:, party:)
      id = Elsewhere::Store.id
      dna = TravelDna.draft(dream_text, date_window, party)
      session = { "id" => id, "dream" => dream_text, "origin" => origin, "date_window" => date_window, "party" => party, "travel_dna" => dna, "clarifications" => [] }
      Elsewhere::Store.sessions[id] = session
      session
    end
    def find(id:); Elsewhere::Store.sessions[id]; end
  end

  module TravelDna
    module_function
    def draft(dream, date_window, _party)
      budget = dream.to_s[/([0-9][0-9 ]*)\s*(?:₽|руб|rub)/i, 1]
      budget = budget ? budget.delete(" ").to_i : 180_000
      elements = [
        element("total_budget", "hard_constraint", budget * 100, nil, "stated", 1.0),
        element("trip_length", "hard_constraint", { "min_nights" => 6, "max_nights" => 7 }, nil, "stated", 0.9),
        element("sea_access", "preference", "high", 0.9, "stated", 0.95),
        element("climate_warm", "preference", "warm", 0.85, "stated", 0.9),
        element("quiet", "preference", "high", 0.85, "stated", 0.9),
        element("food_quality", "preference", "high", 0.75, "stated", 0.85),
        element("walkability", "preference", "high", 0.8, "inferred", 0.7),
        element("crowds", "aversion", "low", 0.65, "inferred", 0.65),
        element("car_free", "hard_constraint", true, nil, "inferred", 0.65),
        element("dates", "hard_constraint", date_window, nil, "stated", 1.0),
        element("party_size", "hard_constraint", party, nil, "stated", 1.0)
      ]
      { "elements" => elements, "unmatched_intent" => [], "clarifications" => [{ "id" => "car_free", "dimension" => "car_free", "question" => "Машина точно недопустима или просто не нужна?", "why_it_matters" => "Это влияет на выбор трансфера и локации.", "options" => [{ "value" => true, "label" => "Без машины" }, { "value" => false, "label" => "Можно машину" }] }] }
    end
    def element(dimension, kind, target, weight, provenance, confidence)
      { "dimension" => dimension, "kind" => kind, "target" => target, "weight" => weight, "tolerance" => nil, "provenance" => provenance, "confidence" => confidence }
    end
    def update(session_id:, elements:)
      dna = { "elements" => elements.map { |e| e.merge("provenance" => e["provenance"] || "confirmed", "confidence" => 1.0) }, "unmatched_intent" => [], "clarifications" => [] }
      Sessions.find(id: session_id)["travel_dna"] = dna
      dna
    end
    def answer_clarifications(session_id:, answers:)
      session = Sessions.find(id: session_id)
      session["travel_dna"]["clarifications"] = []
      session["travel_dna"]
    end
  end

  module Futures
    module_function
    def now; Time.now.utc.iso8601; end
    def generate(session_id:)
      session = Sessions.find(id: session_id)
      choices = [["AER", "prop-sochi-sea", "Море и еда", 92000], ["AER", "prop-sochi-quiet", "Тишина и прогулки", 79000], ["MRV", "prop-mrv-mountain", "Горы и спокойствие", 72000]]
      futures = choices.map.with_index { |choice, index| build(session, choice, index) }
      futures.each { |future| Elsewhere::Store.futures[future["id"]] = future }
      Elsewhere::Store.job("generate_futures", { "kind" => "futures", "futures" => futures })
    end
    def list(session_id:); Elsewhere::Store.futures.values.select { |f| f["session_id"] == session_id }; end
    def find(future_id:); Elsewhere::Store.futures[future_id]; end

    def build(session, choice, index, parent: nil, version: 1)
      city, property_id, why, flight_amount = choice
      property = Supply::Catalog.property(id: property_id)
      nights = 7
      rate = Supply::Rates.for(property_id: property_id, check_in: "2026-07-08", check_out: "2026-07-15", adults: 2)
      transfer = city == "MRV" ? 350000 : 450000
      mobility = city == "MRV" ? 500000 : 250000
      accommodation_amount = rate["amount"]["amount_minor"]
      total = flight_amount + accommodation_amount + transfer + mobility
      match = [0.94, 0.91, 0.87][index] || 0.86
      id = Elsewhere::Store.id
      { "id" => id, "session_id" => session["id"], "lineage_id" => parent ? parent["lineage_id"] : id, "version" => version, "parent_id" => parent && parent["id"], "created_at" => now, "expires_at" => (Time.now + 3600).utc.iso8601, "destination" => destination(city), "check_in" => "2026-07-08", "check_out" => "2026-07-15", "accommodation" => accommodation(property, rate), "logistics" => logistics(session["origin"], city, flight_amount), "price" => price(total, flight_amount, accommodation_amount, transfer, mobility), "match" => match(match, session["travel_dna"]), "why_this_exists" => why, "benefits" => [why], "compromises" => index == 0 ? ["Больше людей в сезон"] : ["Часть поездок потребует транспорта"], "delta" => nil, "forecast_summary" => [] }
    end
    def destination(city); d = Supply::Catalog.destination(city_code: city); { "city_code" => d.city_code, "name" => d.name, "country" => d.country, "coordinates" => d.coordinates }; end
    def accommodation(property, rate); { "catalogue_id" => property.catalogue_id, "name" => property.name, "room_name" => "Стандартный номер", "handoff_url" => rate["handoff_url"], "coordinates" => property.coordinates, "cancellation" => { "refundable" => true, "free_until" => nil, "summary" => "Бесплатная отмена до заезда" }, "distance_to_sea_m" => Supply::Geo.features(property_id: property.catalogue_id)["distance_to_sea_m"], "distance_to_centre_m" => Supply::Geo.features(property_id: property.catalogue_id)["distance_to_centre_m"] }; end
    def logistics(origin, city, amount); { "outbound" => leg(origin, city, amount), "inbound" => leg(city, origin, amount), "airport_transfer" => { "mode" => "shared", "duration_min" => 35, "note" => "Моделируем shared transfer" }, "local_mobility" => { "assumption" => "Основное — пешком, две поездки на такси", "walkable" => true } }; end
    def leg(origin, destination, amount); { "origin" => origin, "destination" => destination, "depart_at" => "2026-07-08T09:00:00Z", "arrive_at" => "2026-07-08T12:00:00Z", "carrier" => "Fixture Air", "stops" => 0, "duration_min" => 180, "amount" => { "amount_minor" => amount, "currency" => "RUB" }, "as_of" => now, "booking_url" => "https://example.invalid/flights" }; end
    def price(total, flight, accommodation, transfer, mobility); { "total" => { "amount_minor" => total, "currency" => "RUB" }, "components" => [{ "kind" => "travel", "amount" => { "amount_minor" => flight, "currency" => "RUB" }, "fulfilment" => "estimate", "source" => "Ignav fixture", "handoff_url" => "https://example.invalid/flights", "as_of" => now }, { "kind" => "accommodation", "amount" => { "amount_minor" => accommodation, "currency" => "RUB" }, "fulfilment" => "modeled", "source" => "harvest calibration", "handoff_url" => nil, "as_of" => nil }, { "kind" => "transfer", "amount" => { "amount_minor" => transfer, "currency" => "RUB" }, "fulfilment" => "modeled", "source" => "shared transfer model", "handoff_url" => nil, "as_of" => nil }, { "kind" => "local_mobility", "amount" => { "amount_minor" => mobility, "currency" => "RUB" }, "fulfilment" => "modeled", "source" => "mobility assumption", "handoff_url" => nil, "as_of" => nil }] }; end
    def match(score, dna); { "score" => score, "confidence" => 0.82, "contributions" => dna["elements"].select { |e| e["weight"] }.map { |e| { "dimension" => e["dimension"], "satisfaction" => score, "weight" => e["weight"], "contribution" => (score * e["weight"]).round(4), "confidence" => e["confidence"], "explanation" => "Рассчитано по данным fixture" } }, "unscored_dimensions" => [{ "dimension" => "food_quality", "reason" => "Нет отзывов в текущем источнике" }] }; end
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
      changed["price"]["total"]["amount_minor"] -= 8_300
      changed["match"]["score"] = (changed["match"]["score"] - 0.02).round(2)
      changed["delta"] = { "from_future_id" => original["id"], "price_before" => original["price"]["total"], "price_after" => changed["price"]["total"], "price_change" => { "amount_minor" => -8300, "currency" => "RUB" }, "items" => [{ "description" => "Отель дальше от моря → экономия на локации", "amount" => { "amount_minor" => -8300, "currency" => "RUB" }, "relaxed_dimension" => "sea_access" }], "match_before" => original["match"]["score"], "match_after" => changed["match"]["score"], "dimension_changes" => [{ "dimension" => "sea_access", "change" => "worsened" }], "new_risks" => [], "resolved_risks" => [], "explanation" => "Снижена цена за счёт наименее важного компромисса." }
      Elsewhere::Store.futures[changed["id"]] = changed
      Elsewhere::Store.job("simulate", { "kind" => "future", "future" => changed })
    end
  end
end
