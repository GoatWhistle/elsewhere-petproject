require_relative "../../../app/values"
require_relative "../../../app/elsewhere/store"
require_relative "../../supply/lib/supply"
require_relative "../../planning/lib/planning"

module Foresight
  module Forecasts
    module_function
    def for_future(future_id:)
      future = Planning::Futures.find(future_id: future_id)
      geo = Supply::Geo.features(property_id: future["accommodation"]["catalogue_id"])
      risk = { "id" => "risk-road-proximity", "risk_type" => "night_noise", "severity" => geo["nearest_major_road_m"].to_i < 300 ? "high" : "low", "confidence" => 0.72, "claim_kind" => "model_inference", "affected_dimension" => "quiet", "statement" => "Близость дороги может повысить вероятность ночного шума; это прокси, а не отзыв о шуме.", "evidence" => [{ "source" => "geo", "excerpt" => "Ближайшая крупная дорога: #{geo["nearest_major_road_m"]} м (#{geo["road_class"]}).", "observed_at" => Date.today.iso8601, "count" => nil }], "mitigations" => [{ "id" => "mitigate-quiet-room", "description" => "Выбрать номер во двор", "price_change" => { "amount_minor" => 3400, "currency" => "RUB" }, "severity_after" => "low" }] }
      { "future_id" => future_id, "generated_at" => Time.now.utc.iso8601, "risks" => [risk], "coverage" => %w[night_noise walkability weather_mismatch transfer_difficulty].map { |type| { "risk_type" => type, "assessed" => type == "night_noise", "reason" => type == "night_noise" ? nil : "В Phase 0 используется только geo fixture" } } }
    end
    def mitigation_adjustment(risk_id:, mitigation_id:); { "dimension" => "quiet", "direction" => "increase", "magnitude" => 0.25 }; end
  end
end
