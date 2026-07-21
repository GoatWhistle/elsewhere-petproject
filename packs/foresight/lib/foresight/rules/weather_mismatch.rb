module Foresight
  module Rules
    # Whether the weather the traveller gets is the weather they asked for. `derived_metric`: thirty years of
    # measurement stand behind the normal, but the mismatch is our comparison against a stated preference.
    # A normal is not a forecast, and the statement says so.
    module WeatherMismatch
      RISK_TYPE = "weather_mismatch".freeze
      DIMENSION = "climate_warm".freeze

      # Below 20 °C a beach holiday is not the one that was booked; below 15 °C it is a different trip (OQ-D).
      WARM_THRESHOLD_C = 20.0
      COOL_THRESHOLD_C = 24.0        # for a traveller who explicitly did not want heat
      WET_MONTH_RAIN_DAYS = 12.0
      SWIMMABLE_SEA_C = 20.0

      module_function

      # `target` is the stated climate preference; without a Travel DNA the rule assumes the trip means warm.
      def call(evidence, target: "warm")
        months = evidence.months
        temperatures = months.map { |month| evidence.climate_value("temp_mean_c", month).to_f }
        mean = temperatures.sum / temperatures.length
        cold_target = target.to_s == "cool" || target.to_s == "cold"

        threshold = cold_target ? COOL_THRESHOLD_C : WARM_THRESHOLD_C
        direction = cold_target ? :above : :below

        Finding.new(
          risk_type: RISK_TYPE, affected_dimension: DIMENSION, claim_kind: "derived_metric",
          measurement: mean.round(1), threshold: threshold, unit: "°C", direction: direction,
          completeness: completeness(evidence, months),
          statement: statement(evidence, months, mean, threshold, cold_target),
          evidence: evidence_lines(evidence, months, mean),
          inputs: { "months" => months, "temp_mean_c" => mean.round(1), "target" => target.to_s }
        )
      end

      def statement(evidence, months, mean, threshold, cold_target)
        base = "Средняя температура в это время — #{mean.round(1)} °C при пороге #{threshold} °C " \
               "(#{cold_target ? "выше" : "ниже"} него это уже не та поездка). " \
               "Это климатическая норма за #{evidence.climate_value("air_years", months.first) || "многолетний период"}, " \
               "а не прогноз: она говорит, каким месяц бывает обычно."
        sea = sea_temperature(evidence, months)
        return base unless sea

        base + (sea < SWIMMABLE_SEA_C ? " Море в среднем #{sea.round(1)} °C — для купания это холодно." : "")
      end

      def evidence_lines(evidence, months, mean)
        lines = [{ "source" => "weather",
                   "excerpt" => "Норма за #{months.map { |m| Date::MONTHNAMES[m] }.join(", ")}: " \
                                "средняя #{mean.round(1)} °C.",
                   "observed_at" => nil,
                   "count" => nil }]

        rain = months.filter_map { |month| evidence.climate_value("rain_days", month)&.to_f }
        if rain.any?
          average = rain.sum / rain.length
          threshold_mm = evidence.climate_value("rain_day_threshold_mm", months.first)
          lines << { "source" => "weather",
                     "excerpt" => "Дней с осадками: #{average.round(1)} в месяц" \
                                  "#{threshold_mm ? " (день с осадками — от #{threshold_mm} мм)" : ""}" \
                                  "#{average > WET_MONTH_RAIN_DAYS ? " — это влажный месяц" : ""}.",
                     "observed_at" => nil, "count" => average.round }
        end

        sea = sea_temperature(evidence, months)
        if sea
          lines << { "source" => "weather",
                     "excerpt" => "Температура моря: #{sea.round(1)} °C" \
                                  "#{sea < SWIMMABLE_SEA_C ? ", ниже комфортных #{SWIMMABLE_SEA_C} °C" : ""}.",
                     "observed_at" => nil, "count" => nil }
        end
        lines
      end

      def sea_temperature(evidence, months)
        values = months.filter_map { |month| evidence.climate_value("sea_temp_c", month)&.to_f }
        return nil if values.empty?

        values.sum / values.length
      end

      # Temperature alone is a thinner claim than temperature plus rain plus sea.
      def completeness(evidence, months)
        available = %w[temp_mean_c rain_days].count { |field| months.all? { |m| evidence.climate_value(field, m) } }
        available += 1 if sea_temperature(evidence, months)
        available / 3.0
      end
    end
  end
end
