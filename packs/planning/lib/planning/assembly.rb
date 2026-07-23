require "date"
require "time"

module Planning
  # Stage 4: dates, fares, and a whole trip. The only stage that costs money, so the bounds are structural: a
  # fare depends on destination and dates, not on the property, so properties in one destination share one
  # request, and at most two date pairs are tried per destination.
  # This stage assembles and never invents. Where Supply publishes a number it is used with its provenance;
  # where Supply publishes nothing — no transfer model, no local-mobility model — the component is absent with
  # the fact stated rather than filled with a plausible figure.
  module Assembly
    MAX_DATE_PAIRS = 2
    DEFAULT_NIGHTS = 7

    # A leg's duration is observed; its clock time is not published, so departure is a fixed reference hour and
    # arrival follows from the duration. The one constructed value in the trip.
    DEPARTURE_HOUR_UTC = 10

    Budget = Struct.new(:fare_requests, keyword_init: true)

    module_function

    # Two date pairs in the window — earliest, and one shifted — so "shift the dates and save" has a comparison.
    def date_pairs(constraints, nights: nil)
      nights ||= constraints.min_nights || DEFAULT_NIGHTS
      window = constraints.date_window
      first = window ? window[:from] : Date.new(2026, 7, 8)
      last = window ? window[:to] : first + nights + 7

      pairs = []
      offset = 0
      while pairs.length < MAX_DATE_PAIRS
        check_in = first + offset
        check_out = check_in + nights
        break if window && check_out > last

        pairs << [check_in, check_out]
        offset += 4
      end
      pairs.empty? ? [[first, first + nights]] : pairs
    end

    def assemble(candidate, constraints, origin:, party:, fares: {}, budget: nil)
      adults = (party && (party["adults"] || party[:adults])) || 2
      best = nil

      date_pairs(constraints).each do |check_in, check_out|
        fare = fare_for(origin, candidate.destination.city_code, check_in, check_out, adults, fares, budget)
        next unless fare && fare["amount"]

        priced = price(candidate, check_in, check_out, adults, fare, origin)
        next if priced.nil?
        return priced if priced["refused"]

        best = priced if best.nil? || cheaper?(priced, best)
      end

      best
    end

    # One fare per destination and date pair, memoised for the whole generation.
    def fare_for(origin, destination, check_in, check_out, adults, fares, budget)
      key = [origin, destination, check_in.to_s, check_out.to_s, adults]
      return fares[key] if fares.key?(key)

      budget&.fare_requests&.<<(key)
      fares[key] = Supply::Flights.price(origin: origin, destination: destination, depart_on: check_in,
                                         return_on: check_out, adults: adults)
    end

    def cheaper?(one, other)
      one.dig("price", "total", "amount_minor") < other.dig("price", "total", "amount_minor")
    end

    def price(candidate, check_in, check_out, adults, fare, origin)
      rate = Supply::Rates.for(property_id: candidate.property.catalogue_id, check_in: check_in.to_s,
                               check_out: check_out.to_s, adults: adults)
      return nil unless rate["amount"]

      components = [travel_component(fare), accommodation_component(rate)]
      currency = components.first["amount"]["currency"]
      # Two currencies need an exchange rate, and nobody has decided whether that rate is observed or modeled.
      # The candidate is refused with the reason rather than summed with an invented one.
      unless components.all? { |component| component["amount"]["currency"] == currency }
        return { "refused" => "разные валюты в одной поездке: перелёт в #{fare["amount"]["currency"]}, " \
                              "проживание в #{rate["amount"]["currency"]} — без курса их нельзя сложить",
                 "candidate" => candidate }
      end

      {
        "check_in" => check_in.to_s, "check_out" => check_out.to_s,
        "logistics" => logistics(candidate, check_in, check_out, fare, origin),
        "price" => { "total" => { "amount_minor" => components.sum { |c| c["amount"]["amount_minor"] },
                                  "currency" => currency },
                     "components" => components },
        "rate" => rate, "fare" => fare, "candidate" => candidate
      }
    end

    # `estimate` means an observed market price we cannot sell; a placeholder fare is not one, so the component
    # follows the fare's own basis rather than assuming every fare was seen.
    def travel_component(fare)
      observed = fare["basis"] == "observed"
      {
        "kind" => "travel", "amount" => fare["amount"],
        "fulfilment" => observed ? "estimate" : "modeled",
        "source" => observed ? "Ignav, наблюдаемый тариф" : "заглушка: наблюдаемого тарифа на этот маршрут нет",
        "handoff_url" => fare["booking_url"], "as_of" => fare["as_of"]
      }
    end

    def accommodation_component(rate)
      { "kind" => "accommodation", "amount" => rate["amount"],
        "fulfilment" => "modeled",
        "source" => "observed base level × modeled seasonality (#{rate.dig("calibration", "model_version")})",
        "handoff_url" => rate["handoff_url"], "as_of" => nil }
    end

    def logistics(candidate, check_in, check_out, fare, origin)
      destination = candidate.destination.city_code
      {
        "outbound" => leg(origin, destination, check_in, fare),
        "inbound" => leg(destination, origin, check_out, fare),
        "airport_transfer" => transfer(candidate),
        "local_mobility" => mobility(candidate)
      }
    end

    def leg(from, to, date, fare)
      depart = Time.utc(date.year, date.month, date.day, DEPARTURE_HOUR_UTC)
      minutes = fare["duration_min"] || 0
      {
        "origin" => from, "destination" => to,
        "depart_at" => depart.iso8601, "arrive_at" => (depart + (minutes * 60)).iso8601,
        "carrier" => fare["carrier"], "stops" => fare["stops"] || 0, "duration_min" => minutes,
        "as_of" => fare["as_of"] || Time.now.utc.iso8601, "booking_url" => fare["booking_url"]
      }
    end

    # Supply's duration when it has one; otherwise the note says distance is all we know, since a transfer time
    # guessed from a straight line is a number nobody measured.
    def transfer(candidate)
      geo = Supply::Geo.features(property_id: candidate.property.catalogue_id) || {}
      minutes = geo["airport_transfer_min"]
      kilometres = geo["airport_distance_m"] ? (geo["airport_distance_m"] / 1000.0).round(1) : nil

      if minutes
        { "mode" => "shared", "duration_min" => minutes.to_i,
          "note" => "Время по дорогам от аэропорта#{kilometres ? ", #{kilometres} км по прямой" : ""}. Стоимость трансфера не моделируется." }
      else
        { "mode" => "shared", "duration_min" => 0,
          "note" => "Времени в пути нет: известно только расстояние#{kilometres ? " — #{kilometres} км по прямой" : ""}. " \
                    "Ни время, ни стоимость трансфера не моделируются." }
      end
    end

    def mobility(candidate)
      geo = Supply::Geo.features(property_id: candidate.property.catalogue_id) || {}
      walkable = geo["poi_density"].to_f >= 0.3
      { "assumption" => walkable ? "В основном пешком: вокруг достаточно точек притяжения" : "Пешком доступно мало — понадобится транспорт",
        "walkable" => walkable }
    end
  end
end
