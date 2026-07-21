module Foresight
  module Rules
    # Road proximity as a proxy for night noise, and the one rule that must never read as a measurement: we
    # measured a distance to a road, not noise, and nobody said their room faces the street. `model_inference`
    # is the honest label.
    module NightNoise
      RISK_TYPE = "night_noise".freeze
      DIMENSION = "quiet".freeze

      # Distance at which each road class stops being a plausible source of night noise: a trunk road carries
      # further than a residential street, so one distance for all classes is wrong both ways. Thresholds,
      # not measurements (OQ-D).
      THRESHOLD_M = { "motorway" => 500, "trunk" => 500, "primary" => 300,
                      "secondary" => 150, "tertiary" => 100 }.freeze
      DEFAULT_THRESHOLD_M = 75

      module_function

      def call(evidence)
        metres = evidence.geo_value("nearest_major_road_m").to_f
        road_class = evidence.geo_value("road_class").to_s
        threshold = THRESHOLD_M.fetch(road_class, DEFAULT_THRESHOLD_M)

        Finding.new(
          risk_type: RISK_TYPE, affected_dimension: DIMENSION, claim_kind: "model_inference",
          measurement: metres, threshold: threshold.to_f, unit: "m", direction: :below,
          completeness: 1.0,
          statement: "Дорога класса #{road_class} проходит в #{metres.round} м — ближе #{threshold} м, " \
                     "с которых шум такой дороги обычно слышен. Это вывод из расстояния: шум не измерялся, " \
                     "и о том, куда выходят окна номера, данных нет.",
          evidence: [{ "source" => "geo",
                       "excerpt" => "Ближайшая крупная дорога: #{metres.round} м, класс #{road_class} " \
                                    "(порог для этого класса — #{threshold} м).",
                       "observed_at" => evidence.geo["computed_at"] || Date.today.iso8601,
                       "count" => nil }],
          inputs: { "nearest_major_road_m" => metres.round, "road_class" => road_class }
        )
      end
    end
  end
end
