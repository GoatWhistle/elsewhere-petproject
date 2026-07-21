module Foresight
  module Rules
    # Whether the area around the property can be lived on foot. `derived_metric`, not `verified_fact`: the POI
    # counts are measured but "walkable" is a computation on top of them. Not `model_inference` either —
    # nothing here reasons about experience, only about what is within 500 m of the door.
    module Walkability
      RISK_TYPE = "walkability".freeze
      DIMENSION = "walkability".freeze

      # Below this density the surroundings stop supplying daily life within a walk. On the measured corpus
      # 0.35 sits just above the first quartile, flagging roughly the emptiest third. Fixed, never recomputed.
      DENSITY_THRESHOLD = 0.35

      # A place can be dense in POIs and still have nowhere to eat, which is the failure this catches.
      RESTAURANTS_THRESHOLD = 5

      module_function

      def call(evidence)
        density = evidence.geo_value("poi_density").to_f
        restaurants = evidence.geo_value("restaurant_count_500m").to_i
        walk_metres = evidence.geo_value("walk_network_m_500m")

        parts = ["в радиусе 500 м плотность точек притяжения #{density.round(2)} (порог #{DENSITY_THRESHOLD})",
                 "ресторанов и кафе: #{restaurants}"]
        parts << "пешеходной сети: #{walk_metres} м" if walk_metres

        Finding.new(
          risk_type: RISK_TYPE, affected_dimension: DIMENSION, claim_kind: "derived_metric",
          measurement: density, threshold: DENSITY_THRESHOLD, unit: "density", direction: :below,
          # Without the street network the same call is made on two measurements instead of three, and the
          # confidence says so.
          completeness: walk_metres ? 1.0 : 2.0 / 3,
          statement: "Пешком отсюда доступно мало: #{parts.join(", ")}. " \
                     "Это расчёт по количеству объектов вокруг, а не оценка того, приятно ли идти.",
          evidence: [{ "source" => "geo",
                       "excerpt" => parts.join("; ") + ".",
                       "observed_at" => evidence.geo["computed_at"] || Date.today.iso8601,
                       "count" => restaurants }],
          inputs: { "poi_density" => density.round(3), "restaurant_count_500m" => restaurants,
                    "walk_network_m_500m" => walk_metres }
        )
      end
    end
  end
end
