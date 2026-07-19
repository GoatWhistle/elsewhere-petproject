require "time"
require "bigdecimal"
require_relative "ignav"

module Supply
  # Flight fares: observed, never invented, and every one carries the moment it was seen. The only paid
  # dependency (DEC-028: ~24 requests a generation, ~40 generations on the free quota), so every answer is
  # written to `flight_fare_snapshots` and read from there first. Tests run in fixture mode.
  module FlightsData
    # A city code is not accepted for fares, so a Moscow origin expands to its airports. Three is the cap:
    # eight destinations × three origins is the 24-request budget exactly.
    MAX_ORIGIN_AIRPORTS = 3

    # No price calendar, so one request per date: three days either side is seven requests for one route.
    MAX_WINDOW_DAYS = 3

    module_function

    def price(origin:, destination:, depart_on:, return_on: nil, adults: 1, cabin_class: "economy",
              cache: PageCache.new, offline: false, market: nil)
      origins = resolve(origin, cache: cache, offline: offline, limit: MAX_ORIGIN_AIRPORTS)
      targets = resolve(destination, cache: cache, offline: offline, limit: 1)

      if origins.empty? || targets.empty?
        return unavailable("could not resolve #{origins.empty? ? origin : destination} to an airport code",
                           offline: offline)
      end

      answers = origins.product(targets).map do |from, to|
        snapshot(from: from, to: to, depart_on: depart_on, return_on: return_on, adults: adults,
                 cabin_class: cabin_class, market: market, cache: cache, offline: offline)
      end

      priced = answers.select { |answer| answer["amount"] }
      return merged_failure(answers, offline: offline) if priced.empty?

      best = priced.min_by { |answer| answer["amount"]["amount_minor"] }
      # Whether any origin had a nonstop, not just the cheapest: "no direct service" is a different claim from
      # "the cheapest option connects".
      best.merge("coverage" => best["coverage"].merge(
        "direct_service" => priced.any? { |answer| answer.dig("coverage", "direct_service") },
        "origins_tried" => origins
      ))
    end

    # The engine behind "shift the dates and save X". One request per date, capped.
    def around_dates(origin:, destination:, depart_on:, window_days: 1, adults: 1,
                     cache: PageCache.new, offline: false, market: nil)
      window = [window_days.to_i, MAX_WINDOW_DAYS].min
      centre = Date.parse(depart_on.to_s)

      ((centre - window)..(centre + window)).map do |date|
        answer = price(origin: origin, destination: destination, depart_on: date, adults: adults,
                       cache: cache, offline: offline, market: market)
        { "date" => date.to_s, "amount" => answer["amount"], "as_of" => answer["as_of"],
          "freshness" => answer["freshness"], "unassessed" => answer["unassessed"] }.compact
      end
    end

    # One origin/destination pair, from the snapshot table if we have it and from Ignav if we do not.
    def snapshot(from:, to:, depart_on:, return_on:, adults:, cabin_class:, market:, cache:, offline:)
      stored = FlightFareSnapshotRecord.find_by(origin: from, destination: to, depart_on: depart_on.to_s,
                                                return_on: return_on&.to_s, adults: adults,
                                                cabin_class: cabin_class)
      return present(stored, freshness: "cached") if stored

      return unavailable("no fare snapshot for #{from}→#{to} on #{depart_on}, and offline", offline: true) if offline

      result = if return_on
                 Ignav.round_trip(origin: from, destination: to, depart_on: depart_on, return_on: return_on,
                                  adults: adults, cabin_class: cabin_class, market: market, cache: cache)
               else
                 Ignav.one_way(origin: from, destination: to, depart_on: depart_on, adults: adults,
                               cabin_class: cabin_class, market: market, cache: cache)
               end
      return unavailable("#{from}→#{to}: #{result.reason}", offline: offline) unless result.ok?

      present(store!(from, to, depart_on, return_on, adults, cabin_class, result), freshness: "live")
    end

    def store!(from, to, depart_on, return_on, adults, cabin_class, result)
      best = cheapest(result.itineraries)
      record = FlightFareSnapshotRecord.find_or_initialize_by(
        origin: from, destination: to, depart_on: depart_on.to_s, return_on: return_on&.to_s,
        adults: adults, cabin_class: cabin_class
      )
      record.assign_attributes(attributes_for(best, result))
      record.save!
      record
    end

    def attributes_for(best, result)
      base = {
        itineraries: result.itineraries.length,
        direct_service: result.itineraries.any? { |itinerary| stops(itinerary).zero? },
        as_of: (Time.parse(result.as_of.to_s) rescue Time.now.utc), source: "ignav"
      }
      return base.merge(unassessed: { "amount" => "the provider returned no itinerary for this route and date" }) if best.nil?

      price = best["price"]
      base.merge(
        amount_minor: (BigDecimal(price["amount"].to_s) * 100).round.to_i,
        currency: price["currency"], price_status: price["status"],
        carrier: best.dig("outbound", "carrier"), duration_min: duration(best),
        stops: stops(best), provider_itinerary_id: best["ignav_id"], unassessed: {}
      )
    end

    def cheapest(itineraries)
      itineraries.select { |itinerary| itinerary.dig("price", "amount") }
                 .min_by { |itinerary| itinerary["price"]["amount"].to_f }
    end

    def duration(itinerary)
      %w[outbound inbound].sum { |leg| itinerary.dig(leg, "duration_minutes").to_i }
    end

    def stops(itinerary)
      %w[outbound inbound].sum do |leg|
        segments = itinerary.dig(leg, "segments")
        segments ? [segments.length - 1, 0].max : 0
      end
    end

    def present(record, freshness:)
      coverage = { "assessed" => true, "itineraries" => record.itineraries,
                   "direct_service" => record.direct_service }
      unless record.direct_service
        # The finding behind DEC-027, carried on every answer rather than left in a document.
        coverage["reason"] = "the provider returned no nonstop itinerary for this route"
      end

      if record.amount_minor.nil?
        return { "amount" => nil, "as_of" => record.as_of&.iso8601, "freshness" => freshness,
                 "coverage" => coverage, "unassessed" => record.unassessed }
      end

      {
        "amount" => { "amount_minor" => record.amount_minor, "currency" => record.currency },
        # Mandatory: a fare we cannot sell is only honest while its age is visible.
        "as_of" => record.as_of.iso8601,
        "carrier" => record.carrier, "duration_min" => record.duration_min, "stops" => record.stops,
        "booking_url" => record.booking_url, "provider_itinerary_id" => record.provider_itinerary_id,
        "basis" => "observed", "price_status" => record.price_status,
        "freshness" => freshness, "coverage" => coverage
      }
    end

    # City code → airport codes. Airport search accepts a city code even though fares do not; a queried code
    # that comes back in the results was already an airport.
    def resolve(code, cache:, offline:, limit:)
      code = code.to_s.upcase
      result = Ignav.airports(code, cache: cache, offline: offline)
      return [code] unless result.ok?

      found = result.airports || []
      return [code] if found.any? { |airport| airport["code"] == code }

      city = found.first && found.first["city"]
      found.select { |airport| airport["city"] == city }.map { |airport| airport["code"] }.first(limit)
    end

    def unavailable(reason, offline:)
      { "amount" => nil, "as_of" => nil, "freshness" => offline ? "cached" : "live",
        "coverage" => { "assessed" => false, "reason" => reason },
        "unassessed" => { "amount" => reason } }
    end

    def merged_failure(answers, offline:)
      reasons = answers.filter_map { |answer| answer.dig("unassessed", "amount") }.uniq
      unavailable(reasons.join("; "), offline: offline)
    end
  end
end
