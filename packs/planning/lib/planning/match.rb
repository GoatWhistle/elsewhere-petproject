require_relative "curves"
require_relative "taxonomy"

module Planning
  # Experience Match (DEC-020/021/024). score = Σ(wᵢ×sᵢ)/Σ(wᵢ) over scored dimensions,
  # coverage = Σ(scored weights)/Σ(all weights), confidence = coverage × weighted mean of confidences.
  # Normalized against a fixed ideal, never against the candidate set: a moving denominator invents deltas.
  # Nothing scores 98%; the band is 0.6–0.9 and is not rescaled. No model touches this.
  module Match
    MEASURED = 0.9   # a number we read off a measurement
    PROXY = 0.6      # a number standing in for one we cannot measure; capped by DEC-024

    # Scores within this are equal; coverage then breaks the tie, so ignorance costs something (DEC-021).
    TIE_THRESHOLD = 0.02

    Features = Struct.new(:geo, :rating, :temperature, :sources, keyword_init: true)

    module_function

    def features_for(property:, city_code:, months:)
      geo = Supply::Geo.features(property_id: property.catalogue_id) || {}
      temperatures = Array(months).filter_map do |month|
        (Supply::Climate.normals(city_code: city_code, month: month) || {})["temp_mean_c"]
      end

      Features.new(geo: geo, rating: property.rating,
                   temperature: temperatures.any? ? temperatures.sum.to_f / temperatures.length : nil)
    end

    def score(dna:, features:)
      elements = Array(dna["elements"]).reject { |element| Taxonomy.hard?(element["dimension"]) }
      assessed = elements.map { |element| assess(element, features) }

      scored = assessed.select { |entry| entry[:satisfaction] }
      unscored = assessed - scored

      total_weight = elements.sum { |element| element["weight"].to_f }
      scored_weight = scored.sum { |entry| entry[:weight] }

      {
        "score" => overall(scored, scored_weight),
        "coverage" => total_weight.zero? ? 0.0 : (scored_weight / total_weight).round(4),
        "confidence" => confidence(scored, scored_weight, total_weight),
        "contributions" => scored.map { |entry| contribution(entry) },
        "unscored_dimensions" => unscored.map { |entry| { "dimension" => entry[:dimension], "reason" => entry[:reason] } }
      }
    end

    # Σ(w×s)/Σ(w). An aversion contributes −w..+w, not 0..w: a violated aversion must pull the score down.
    def overall(scored, scored_weight)
      return 0.0 if scored_weight.zero?

      total = scored.sum { |entry| signed_contribution(entry) }
      (total / scored_weight).clamp(0.0, 1.0).round(4)
    end

    def signed_contribution(entry)
      return entry[:weight] * ((entry[:satisfaction] * 2) - 1) if entry[:kind] == "aversion"

      entry[:weight] * entry[:satisfaction]
    end

    def confidence(scored, scored_weight, total_weight)
      return 0.0 if scored_weight.zero? || total_weight.zero?

      weighted_mean = scored.sum { |entry| entry[:weight] * entry[:confidence] } / scored_weight
      ((scored_weight / total_weight) * weighted_mean).round(4)
    end

    def contribution(entry)
      {
        "dimension" => entry[:dimension], "satisfaction" => entry[:satisfaction].round(4),
        "weight" => entry[:weight].round(4), "contribution" => signed_contribution(entry).round(4),
        "confidence" => entry[:confidence], "explanation" => entry[:explanation]
      }
    end

    # Sort key, better first (DEC-021). Scores are bucketed rather than compared pairwise: "within 0.02" is
    # not transitive, and a non-transitive comparator makes the order depend on the input order.
    def ranking_key(match) = [-bucket(match["score"]), -match["coverage"].to_f]

    def bucket(score) = (score.to_f / TIE_THRESHOLD).floor

    def better?(one, other) = (ranking_key(one) <=> ranking_key(other)).negative?

    # ---- one dimension ------------------------------------------------------------------------------------

    def assess(element, features)
      dimension = element["dimension"]
      weight = element["weight"].to_f
      base = { dimension: dimension, weight: weight, kind: element["kind"] }

      value = send("assess_#{dimension}", element, features)
      return base.merge(satisfaction: nil, reason: value) if value.is_a?(String)

      base.merge(value)
    end

    def assess_sea_access(_element, features)
      distance = features.geo["distance_to_sea_m"]
      # Absent is not unmeasured: no sea is a known fact, and calling it unknown would inflate coverage on the
      # destinations that cannot deliver it (DEC-024).
      return { satisfaction: 0.0, confidence: MEASURED, explanation: "У этого направления нет побережья" } if distance.nil? && landlocked?(features)
      return "нет данных о расстоянии до моря" if distance.nil?

      { satisfaction: Curves.more_is_better("sea_access", distance), confidence: MEASURED,
        explanation: "До моря #{distance} м" }
    end

    def landlocked?(features) = features.geo.key?("distance_to_sea_m") || features.geo["freshness"].present?

    def assess_food_quality(_element, features)
      count = features.geo["restaurant_count_500m"]
      return "нет данных о заведениях рядом" if count.nil?

      { satisfaction: Curves.more_is_better("food_quality", count), confidence: MEASURED,
        explanation: "#{count} кафе и ресторанов в 500 м" }
    end

    def assess_walkability(_element, features)
      count = poi_count(features)
      return "нет данных о плотности точек притяжения" if count.nil?

      satisfaction = Curves.more_is_better("walkability", count)
      centre = features.geo["distance_to_centre_m"]
      capped = centre && centre > 3000
      { satisfaction: capped ? [satisfaction, 0.6].min : satisfaction, confidence: MEASURED,
        explanation: "≈#{count.round} точек притяжения в пешей доступности" +
                     (capped ? ", но до центра #{(centre / 1000.0).round(1)} км" : "") }
    end

    # Supply gives a count where it has one, else density `d = n/(n+200)` per km²; a 500 m circle is 0.785 km².
    AREA_500M_KM2 = 0.785

    def poi_count(features)
      return features.geo["poi_count_500m"] if features.geo["poi_count_500m"]
      return features.geo["poi_per_km2"].to_f * AREA_500M_KM2 if features.geo["poi_per_km2"]

      density = features.geo["poi_density"]
      return nil if density.nil?

      # A saturated density is the densest place known, not an unknown one: never fail into "no data" here.
      value = density.to_f.clamp(0.0, 0.999)
      (200.0 * value / (1 - value)) * AREA_500M_KM2
    end

    def assess_quiet(_element, features)
      metres = features.geo["nearest_major_road_m"]
      road_class = features.geo["road_class"]
      return "нет данных о ближайшей дороге" if metres.nil? && road_class.nil?

      { satisfaction: Curves.quiet(metres, road_class),
        # A road distance is not a measurement of noise, so DEC-024 caps this dimension.
        confidence: PROXY,
        explanation: "Ближайшая крупная дорога: #{metres || "нет"} м (#{road_class || "только местные"}); " \
                     "это прокси по расстоянию, а не измерение шума" }
    end

    def assess_comfort(_element, features)
      rating = features.rating
      return "у объекта нет рейтинга" if rating.nil?

      { satisfaction: Curves.more_is_better("comfort", normalised_rating(rating)), confidence: MEASURED,
        explanation: "Рейтинг объекта #{rating}" }
    end

    # The harvest publishes ratings on a ten-point scale; the curve is written on five.
    def normalised_rating(rating) = rating.to_f > 5.0 ? rating.to_f / 2 : rating.to_f

    def assess_transfer_simplicity(_element, features)
      metres = features.geo["airport_distance_m"]
      return "нет данных о расстоянии до аэропорта" if metres.nil?

      { satisfaction: Curves.more_is_better("transfer_simplicity", metres), confidence: MEASURED,
        explanation: "Аэропорт в #{(metres / 1000.0).round(1)} км" }
    end

    def assess_climate_warm(element, features)
      temperature = features.temperature
      return "нет климатической нормы на эти даты" if temperature.nil?

      { satisfaction: Curves.climate(temperature), confidence: MEASURED,
        explanation: "Средняя температура #{temperature.round(1)} °C при желаемых #{element["target"]} °C" }
    end

    def assess_nature_vs_city(element, features)
      count = poi_count(features)
      return "нет данных о плотности застройки" if count.nil?

      cityness = (count / 300.0).clamp(0.0, 1.0)
      { satisfaction: Curves.target_match("nature_vs_city", element["target"], cityness),
        # POI density alone: the green share is not in the OSM layers we import.
        confidence: PROXY,
        explanation: "Городская плотность ≈#{cityness.round(2)} по числу точек притяжения; " \
                     "доля зелени не измеряется" }
    end

    def assess_crowds(_element, _features)
      "толпы не измеряются: нужна сезонность и популярность направления, а их Supply не публикует"
    end

    def assess_nightlife(_element, _features)
      "нет данных о барах и клубах: в импорте OSM нет отдельного слоя"
    end
  end
end
