require "bigdecimal"
require "date"

module Supply
  # The room rate (DEC-029): observed base level × seasonal factor (climate + popularity) × nights.
  # Only the base is observed — "busier season costs more" is a hypothesis, so the wording is "base observed,
  # seasonality modeled", never "calibrated on observed prices". The one synthetic number in the product.
  # `freshness` has no `modeled` value: `cached` says the calibration inputs came from stored data, while
  # `basis: "modeled"` identifies the output. Deterministic: a stored row per destination and month times an
  # integer, so a Simulator delta cannot drift on its own.
  module RateModel
    # Bump when the formula changes: old calibrations stay readable and every Rate names the one that made it.
    VERSION = "seasonal-v2".freeze

    # The bounds DEC-029 asks for. A factor cannot leave them whatever the inputs do.
    FACTOR_MIN = 0.70
    FACTOR_MAX = 1.60

    # How far the factor may swing. Popularity does not move the price on its own; it sets how seasonal a
    # place is.
    AMPLITUDE_MIN = 0.15
    AMPLITUDE_MAX = 0.45
    MODELED_FRESHNESS = "cached".freeze

    # Reviews per property at which a destination is half-way to "busy". Fixed: a denominator drawn from the
    # current corpus would rescore every existing Future as the corpus grew.
    POPULARITY_HALF_SATURATION = 300.0

    # A 25 °C annual swing reaches the maximum climate contribution; a place with stable weather cannot reach
    # the seasonal range of one whose climate actually moves.
    SEASONAL_RANGE_REFERENCE_C = 25.0

    module_function

    # Builds one calibration row per destination and month. Cheap and local — climate normals are already stored.
    def calibrate!(city_codes: nil, log: nil)
      written = 0

      DestinationRecord.order(:city_code).then { |s| city_codes ? s.where(city_code: city_codes) : s }.each do |destination|
        normals = DestinationClimateNormalRecord.where(city_code: destination.city_code).order(:month).to_a
        if normals.length < 12
          log&.call("#{destination.city_code}: #{normals.length}/12 climate normals — skipped")
          next
        end

        temperatures = normals.map { |normal| normal.temp_mean_c.to_f }
        popularity = popularity_for(destination)
        seasonal_swing = seasonal_swing(temperatures)
        amplitude = amplitude_for(popularity: popularity, seasonal_swing: seasonal_swing)

        normals.each do |normal|
          comfort = comfort_for(normal, temperatures, destination.peak_season)
          factor = clamp(1 + amplitude * ((comfort * 2) - 1))

          record = PriceCalibrationRecord.find_or_initialize_by(
            city_code: destination.city_code, month: normal.month, model_version: VERSION
          )
          record.update!(
            comfort: comfort.round(3), popularity: popularity.round(3), amplitude: amplitude.round(3),
            seasonal_factor: factor,
            inputs: {
              "temp_mean_c" => normal.temp_mean_c.to_f, "sea_temp_c" => normal.sea_temp_c&.to_f,
              "peak_season" => destination.peak_season, "reviews_per_property" => reviews_per_property(destination),
              "annual_temp_range_c" => [temperatures.min, temperatures.max],
              "seasonal_swing" => seasonal_swing.round(3),
              "basis" => "the base is observed; this seasonality is modeled"
            },
            computed_at: Time.now.utc
          )
          written += 1
        end
        log&.call("#{destination.city_code}: 12 months, factor #{months_range(destination.city_code)}")
      end

      written
    end

    # How much this month suits this destination, 0 to 1. Read against the destination's own annual range, and
    # directed by the declared `peak_season`: for a ski resort the comfortable month is the cold one.
    def comfort_for(normal, temperatures, peak_season)
      low, high = temperatures.minmax
      return 0.5 if (high - low).abs < 0.01

      warmth = (normal.temp_mean_c.to_f - low) / (high - low)
      # A sea destination sells the water, not the air, so the sea leads where we have measured it.
      if normal.sea_temp_c
        sea = sea_warmth(normal, temperatures)
        warmth = (0.4 * warmth) + (0.6 * sea) if sea
      end

      peak_season == "cold" ? 1 - warmth : warmth
    end

    def sea_warmth(normal, _temperatures)
      series = DestinationClimateNormalRecord.where(city_code: normal.city_code)
                                             .where.not(sea_temp_c: nil).pluck(:sea_temp_c).map(&:to_f)
      return nil if series.length < 2

      low, high = series.minmax
      return nil if (high - low).abs < 0.01

      (normal.sea_temp_c.to_f - low) / (high - low)
    end

    def popularity_for(destination)
      reviews = reviews_per_property(destination)
      return 0.0 if reviews.nil?

      reviews / (reviews + POPULARITY_HALF_SATURATION)
    end

    def seasonal_swing(temperatures)
      ((temperatures.max.to_f - temperatures.min.to_f) / SEASONAL_RANGE_REFERENCE_C).clamp(0.0, 1.0)
    end

    def amplitude_for(popularity:, seasonal_swing:)
      AMPLITUDE_MIN + (AMPLITUDE_MAX - AMPLITUDE_MIN) * popularity.to_f * seasonal_swing.to_f
    end

    def reviews_per_property(destination)
      counts = PropertyRecord.where(destination_id: destination.id).pluck(:review_count).compact
      return nil if counts.empty?

      counts.sum.to_f / counts.length
    end

    def clamp(value) = value.clamp(FACTOR_MIN, FACTOR_MAX).round(3)

    def months_range(city_code)
      factors = PriceCalibrationRecord.where(city_code: city_code, model_version: VERSION)
                                      .pluck(:seasonal_factor).map(&:to_f)
      factors.empty? ? "-" : "#{factors.min}–#{factors.max}"
    end

    # Nights are priced one at a time, so a stay crossing a month boundary is exact.
    def for(property_id:, check_in:, check_out:, adults: 1)
      property = PropertyRecord.find_by(catalogue_id: property_id)
      return unavailable("unknown property #{property_id}") unless property

      base = property.price_level_minor
      return unavailable(property.price_level_note || "this property has no observed price level") unless base

      nights = (Date.parse(check_out.to_s) - Date.parse(check_in.to_s)).to_i
      return unavailable("check_out must be after check_in") unless nights.positive?

      calibrations = calibrations_for(property.city_code)
      return unavailable("no calibration for #{property.city_code} — run Supply::RateModel.calibrate!") if calibrations.empty?

      nightly = (0...nights).map do |offset|
        date = Date.parse(check_in.to_s) + offset
        factor = calibrations[date.month]
        return unavailable("no calibration for #{property.city_code} month #{date.month}") unless factor

        { "date" => date.to_s, "factor" => factor, "amount_minor" => (base * factor).round }
      end

      total = nightly.sum { |night| night["amount_minor"] }
      present(property, base, nights, nightly, total, adults)
    end

    def present(property, base, nights, nightly, total, adults)
      factors = nightly.map { |night| night["factor"] }
      mean = factors.sum / factors.length

      {
        "amount" => { "amount_minor" => total, "currency" => property.price_currency || "RUB" },
        # The one synthetic number in this product, and it says so everywhere it appears (rule 7).
        "basis" => "modeled",
        "calibration" => { "model_version" => VERSION, "city_code" => property.city_code,
                           "seasonal_factor_mean" => mean.round(3), "nights" => nights,
                           "observed_base_minor" => base,
                           "statement" => "the base is observed; the seasonality is modeled" },
        # Enough to answer "why this number": base, factor per night, and the split.
        "explanation" => {
          "observed_base_minor" => base, "nights" => nights,
          "seasonal_change_pct" => ((mean - 1) * 100).round,
          "per_night" => nightly
        },
        "handoff_url" => property.source_url,
        "freshness" => MODELED_FRESHNESS,
        # A room is a room: the base is per room per night, and party size does not change it here.
        "unassessed" => adults.to_i > 1 ? { "occupancy" => "the observed base is per room; it is not adjusted for party size" } : {}
      }
    end

    def calibrations_for(city_code)
      PriceCalibrationRecord.where(city_code: city_code, model_version: VERSION)
                            .pluck(:month, :seasonal_factor).to_h { |month, factor| [month, factor.to_f] }
    end

    def unavailable(reason)
      { "amount" => nil, "basis" => "modeled", "freshness" => MODELED_FRESHNESS,
        "calibration" => { "model_version" => VERSION }, "unassessed" => { "amount" => reason } }
    end
  end
end
