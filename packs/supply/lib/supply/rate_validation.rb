module Supply
  # Is the room rate defensible against the observed levels it stands on? (OQ-A — Supply and Foresight jointly.)
  #
  # The rate is the one synthetic number in the product, so these are properties that must hold on the real
  # corpus, each able to fail. What cannot be checked: whether a July night in Sochi really costs 28% more than
  # the "from" price — that needs observed dated prices no free source has (DEC-016, DEC-029). The seasonality
  # stays a hypothesis; what is verifiable is that it never runs away from the observed anchor.
  module RateValidation
    # Averaged over a year the factor should be about 1, or the model is restating every harvested price.
    BIAS_TOLERANCE = 0.05

    # "Shift your dates and save" needs a real spread to work with. Below this the mechanic is decorative.
    MIN_SEASONAL_SPREAD = 1.4

    Check = Struct.new(:name, :passed, :detail, keyword_init: true)

    module_function

    def report(calibrations: nil, price_levels: nil)
      calibrations ||= from_database
      price_levels ||= levels_from_database
      by_city = calibrations.group_by { |row| row["city_code"] }

      checks = [
        anchored(by_city),
        unbiased(by_city),
        seasonal_spread(by_city),
        rank_preserving(by_city, price_levels)
      ]

      { "model_version" => RateModel::VERSION, "destinations" => by_city.keys.sort,
        "checks" => checks.map { |check| check.to_h.transform_keys(&:to_s) },
        "passed" => checks.all?(&:passed) }
    end

    # 1. Every modeled rate stays inside the corridor DEC-029 declared around the observed base.
    def anchored(by_city)
      factors = by_city.values.flatten.map { |row| row["seasonal_factor"].to_f }
      outside = factors.reject { |factor| factor.between?(RateModel::FACTOR_MIN, RateModel::FACTOR_MAX) }

      Check.new(name: "anchored to the observed base", passed: outside.empty?,
                detail: "#{factors.length} factors in #{factors.min}–#{factors.max}, " \
                        "bounds #{RateModel::FACTOR_MIN}–#{RateModel::FACTOR_MAX}")
    end

    # 2. Over a full year the factor averages about 1, so the model neither inflates nor deflates the harvest.
    def unbiased(by_city)
      means = by_city.transform_values do |rows|
        factors = rows.map { |row| row["seasonal_factor"].to_f }
        (factors.sum / factors.length).round(4)
      end
      worst = means.max_by { |_city, mean| (mean - 1).abs }

      Check.new(name: "unbiased over a year", passed: (worst.last - 1).abs <= BIAS_TOLERANCE,
                detail: means.map { |city, mean| "#{city} #{mean}" }.join(" · ") +
                        " (tolerance ±#{BIAS_TOLERANCE})")
    end

    # 3. There is a real high and low season to shift between.
    def seasonal_spread(by_city)
      spreads = by_city.transform_values do |rows|
        factors = rows.map { |row| row["seasonal_factor"].to_f }
        (factors.max / factors.min).round(2)
      end
      thin = spreads.select { |_city, spread| spread < MIN_SEASONAL_SPREAD }

      Check.new(name: "a season worth shifting", passed: thin.empty?,
                detail: spreads.map { |city, spread| "#{city} ×#{spread}" }.join(" · ") +
                        " (minimum ×#{MIN_SEASONAL_SPREAD})")
    end

    # "Calibrated per property, not a global formula" is not checked here: with `rate = base × factor` it
    # cannot fail on this data. It is asserted end to end through Supply::Rates in this module's spec.
    #
    # 4. The model must not reorder the corpus: a property observed cheaper stays cheaper in every month, or the
    #    cheap/expensive axis stops meaning anything the moment a date is chosen.
    def rank_preserving(by_city, price_levels)
      broken = by_city.keys.sort.reject do |city|
        bases = Array(price_levels[city]).sort
        next true if bases.length < 2

        by_city[city].all? do |row|
          rated = bases.map { |base| (base * row["seasonal_factor"].to_f).round }
          rated == rated.sort
        end
      end

      Check.new(name: "order of the corpus preserved", passed: broken.empty?,
                detail: broken.empty? ? "every destination keeps its price order in all 12 months" : broken.join(", "))
    end

    def from_database
      PriceCalibrationRecord.where(model_version: RateModel::VERSION)
                            .pluck(:city_code, :month, :seasonal_factor)
                            .map { |city, month, factor| { "city_code" => city, "month" => month, "seasonal_factor" => factor.to_f } }
    end

    def levels_from_database
      PropertyRecord.where.not(price_level_minor: nil).pluck(:city_code, :price_level_minor)
                    .group_by(&:first).transform_values { |rows| rows.map(&:last) }
    end
  end
end
