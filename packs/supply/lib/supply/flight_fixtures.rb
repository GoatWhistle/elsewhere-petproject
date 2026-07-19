require "json"
require "bigdecimal"

module Supply
  # Fares in fixture mode, from real captured Ignav responses: inventing a response shape would make the
  # adapter boundary fiction, so every file here is one the provider sent, byte for byte. The corpus is larger
  # than the captured routes, so an uncaptured route answers as a placeholder that says so, never as observed.
  module FlightFixtures
    DIRECTORY = File.expand_path("../../fixtures/ignav", __dir__).freeze

    # Captured route → file, all at the default market, the only one returning the carriers that fly these
    # routes; `market_ru/` holds the set that does not, kept as evidence for the research log. Moscow's
    # airports stay apart: SVO has no nonstop to Sochi while DME and VKO do, and collapsing them would price a
    # 17-hour connection via Abu Dhabi as the answer.
    CAPTURES = {
      %w[SVO AER] => "SVO_AER", %w[DME AER] => "DME_AER", %w[VKO AER] => "VKO_AER",
      %w[SVO IST] => "SVO_IST", %w[LHR BCN] => "LHR_BCN"
    }.freeze
    ROUND_TRIP = { %w[LHR BCN] => "LHR_BCN_rt" }.freeze

    # Stand-ins for uncaptured routes, kept so the walking skeleton still walks.
    PLACEHOLDER_MINOR = { "AER" => 3_200_000, "MRV" => 2_500_000, "AAQ" => 2_800_000,
                          "KGD" => 2_400_000, "KZN" => 1_900_000, "NOZ" => 4_100_000 }.freeze
    PLACEHOLDER_DEFAULT = 1_800_000

    module_function

    # A city code expands the way live mode expands it, and the best of the three wins — see above.
    CITY_AIRPORTS = { "MOW" => %w[DME SVO VKO] }.freeze

    def price(origin:, destination:, depart_on:, return_on: nil, adults: 1, **options)
      from = origin.to_s.upcase
      if (airports = CITY_AIRPORTS[from])
        priced = airports.map do |airport|
          price(origin: airport, destination: destination, depart_on: depart_on, return_on: return_on,
                adults: adults, **options)
        end
        best = priced.select { |answer| answer.dig("coverage", "assessed") }
                     .min_by { |answer| answer["amount"]["amount_minor"] }
        return best.merge("coverage" => best["coverage"].merge("origins_tried" => airports)) if best

        return priced.first
      end

      route = [from, destination.to_s.upcase]
      file = (return_on && ROUND_TRIP[route]) || CAPTURES[route]
      return placeholder(route, adults) unless file

      captured = load(file)
      itinerary = FlightsData.cheapest(captured["itineraries"] || [])
      return placeholder(route, adults) unless itinerary

      {
        "amount" => { "amount_minor" => (BigDecimal(itinerary["price"]["amount"].to_s) * 100).round.to_i * adults.to_i,
                      "currency" => itinerary["price"]["currency"] },
        "as_of" => captured_at(file),
        "carrier" => itinerary.dig("outbound", "carrier"),
        "duration_min" => FlightsData.duration(itinerary),
        "stops" => FlightsData.stops(itinerary),
        "booking_url" => nil,
        "provider_itinerary_id" => itinerary["ignav_id"],
        "basis" => "observed", "price_status" => itinerary.dig("price", "status"),
        "freshness" => "fixture",
        "coverage" => coverage_for(captured)
      }
    end

    def around_dates(origin:, destination:, depart_on:, window_days: 1, **options)
      centre = Date.parse(depart_on.to_s)
      window = [window_days.to_i, FlightsData::MAX_WINDOW_DAYS].min
      ((centre - window)..(centre + window)).map do |date|
        answer = price(origin: origin, destination: destination, depart_on: date, **options)
        { "date" => date.to_s, "amount" => answer["amount"], "as_of" => answer["as_of"],
          "freshness" => "fixture" }
      end
    end

    def coverage_for(captured)
      itineraries = captured["itineraries"] || []
      direct = itineraries.any? { |itinerary| FlightsData.stops(itinerary).zero? }
      coverage = { "assessed" => true, "itineraries" => itineraries.length, "direct_service" => direct }
      coverage["reason"] = "the provider returned no nonstop itinerary for this route" unless direct
      coverage
    end

    def placeholder(route, adults)
      {
        "amount" => { "amount_minor" => (PLACEHOLDER_MINOR[route.last] || PLACEHOLDER_DEFAULT) * adults.to_i,
                      "currency" => "RUB" },
        "as_of" => nil, "carrier" => nil, "duration_min" => nil, "stops" => nil, "booking_url" => nil,
        # Never "observed": nobody observed this.
        "basis" => "modeled", "freshness" => "fixture",
        "coverage" => { "assessed" => false,
                        "reason" => "Phase 0 placeholder — no captured Ignav response for #{route.join("→")}" },
        "unassessed" => { "as_of" => "a placeholder was never observed, so it has no observation time" }
      }
    end

    def load(file) = JSON.parse(File.read(File.join(DIRECTORY, "#{file}.json")))

    # The date of the probe: the captures are what the provider said then, and the age is part of the fact.
    def captured_at(_file) = "2026-08-27T14:00:00Z"
  end
end
