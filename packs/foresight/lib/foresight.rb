require "date"
require "time"
require_relative "../../shared/lib/elsewhere/values"
require_relative "../../supply/lib/supply"
require_relative "../../planning/lib/planning"
require_relative "foresight/evidence"

module Foresight
  # What could go wrong for this person, stated with its evidence or not stated at all. There is no review
  # source (C-05), so the qualitative layer behind "street noise after 23:00" is gone; what is left is geo and
  # climate, and the rest is reported as unassessed.
  module Forecasts
    # Every type the contract knows. A forecast answers for all of them — with a risk, or with a reason.
    ALL_RISK_TYPES = Elsewhere::Values::RISK_TYPES

    module_function

    def for_future(future_id:)
      future = Planning::Futures.find(future_id: future_id)
      evidence = Evidence.for_future(future)

      {
        "future_id" => future_id,
        "generated_at" => Time.now.utc.iso8601,
        "risks" => risks(future, evidence),
        "coverage" => coverage(evidence)
      }
    end

    def risks(_future, evidence)
      return [] unless evidence.available?("night_noise")

      [night_noise(evidence)]
    end

    # Every risk type says whether it was assessed and why not, in the words of whatever refused to answer.
    # Four can only be evidenced by review text, so they always carry Supply's reason for having none.
    def coverage(evidence)
      ALL_RISK_TYPES.map do |risk_type|
        assessed = evidence.available?(risk_type)
        entry = { "risk_type" => risk_type, "assessed" => assessed }
        entry["reason"] = evidence.unavailable_reason(risk_type) unless assessed
        entry
      end
    end

    def night_noise(evidence)
      metres = evidence.geo_value("nearest_major_road_m").to_i
      road_class = evidence.geo_value("road_class")

      {
        "id" => "risk-night_noise",
        "risk_type" => "night_noise",
        "severity" => metres < 300 ? "high" : "low",
        "confidence" => 0.5,
        # A road distance is measured; "the room will be noisy" is reasoning on top of it. The label is the
        # difference between a forecast and a rumour, and it never gets upgraded by how sure the prose sounds.
        "claim_kind" => "model_inference",
        "affected_dimension" => "quiet",
        "statement" => "Рядом проходит дорога класса #{road_class} — это повышает вероятность ночного шума. " \
                       "Это вывод из расстояния, а не измерение шума и не отзыв.",
        "evidence" => [
          {
            "source" => "geo",
            "excerpt" => "Ближайшая крупная дорога: #{metres} м (#{road_class}).",
            "observed_at" => Date.today.iso8601,
            "count" => nil
          }
        ],
        "mitigations" => [
          { "id" => "mitigate-quiet-room", "description" => "Выбрать номер во двор",
            "price_change" => { "amount_minor" => 3400, "currency" => "RUB" }, "severity_after" => "low" }
        ]
      }
    end

    def mitigation_adjustment(risk_id:, mitigation_id:)
      { "dimension" => "quiet", "direction" => "increase", "magnitude" => 0.25 }
    end
  end
end
