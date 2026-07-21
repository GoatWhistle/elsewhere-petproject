require "rails_helper"

RSpec.describe Foresight::Mitigations do
  let(:future) do
    { "id" => "11111111-1111-1111-1111-111111111111", "session_id" => "s1",
      "accommodation" => { "catalogue_id" => "prop-sochi-sea" },
      "destination" => { "city_code" => "AER" },
      "check_in" => "2026-07-08", "check_out" => "2026-07-15" }
  end

  def forecast(geo: nil, climate: nil)
    allow(Planning::Futures).to receive(:find).and_return(future)
    allow(Planning::Sessions).to receive(:find).and_return(nil)
    allow(Supply::Geo).to receive(:features).and_call_original
    allow(Supply::Geo).to receive(:features).with(property_id: "prop-sochi-sea").and_return(geo) if geo
    allow(Supply::Climate).to receive(:normals).and_call_original
    if climate
      allow(Supply::Climate).to receive(:normals).with(city_code: "AER", month: 7).and_return(climate)
    end

    Foresight::Forecasts.for_future(future_id: future["id"])
  end

  # The Sochi fixture property sits 220 m from a primary road; its quiet neighbour is 700 m from a secondary.
  let(:noisy_geo) do
    { "nearest_major_road_m" => 40, "road_class" => "primary", "distance_to_sea_m" => 140,
      "poi_density" => 0.9, "restaurant_count_500m" => 28, "airport_distance_m" => 28_000,
      "freshness" => "fixture" }
  end

  describe "a mitigation that came from the risk" do
    let(:risk) { forecast(geo: noisy_geo)["risks"].find { |r| r["risk_type"] == "night_noise" } }
    let(:mitigation) { risk["mitigations"].first }

    it "names a real alternative and what it changes" do
      expect(mitigation["description"]).to include("Тихий двор")
      expect(mitigation["description"]).to include("700 м вместо 40 м")
    end

    it "recomputes severity against that alternative rather than asserting an improvement" do
      expect(risk["severity"]).to eq("high")
      expect(mitigation["severity_after"]).to eq("low")
    end

    it "prices the swap from two rates Supply quotes, not from a guess" do
      here = Supply::Rates.for(property_id: "prop-sochi-sea", check_in: "2026-07-08", check_out: "2026-07-15", adults: 2)
      there = Supply::Rates.for(property_id: "prop-sochi-quiet", check_in: "2026-07-08", check_out: "2026-07-15", adults: 2)

      expect(mitigation["price_change"]["amount_minor"])
        .to eq(there["amount"]["amount_minor"] - here["amount"]["amount_minor"])
      expect(mitigation["price_change"]["amount_minor"]).to be_negative   # the quiet one is cheaper
    end
  end

  describe "mitigations differ by risk" do
    it "offers a different fix for a cold month than for a loud road" do
      cold = forecast(geo: { "nearest_major_road_m" => 900, "road_class" => "secondary",
                             "poi_density" => 0.9, "restaurant_count_500m" => 28,
                             "airport_distance_m" => 28_000, "freshness" => "fixture" },
                      climate: { "temp_mean_c" => 8.0, "rain_days" => 18.0, "freshness" => "fixture" })
      weather = cold["risks"].find { |risk| risk["risk_type"] == "weather_mismatch" }
      noise = forecast(geo: noisy_geo)["risks"].find { |risk| risk["risk_type"] == "night_noise" }

      expect(weather["mitigations"].first["description"]).to include("Перенести поездку")
      expect(noise["mitigations"].first["description"]).to include("Взять другой объект")
      expect(weather["mitigations"].first["id"]).not_to eq(noise["mitigations"].first["id"])
    end

    it "pushes harder on a worse risk" do
      severe = described_class.adjustment(finding_with(measurement: 40, threshold: 300), "x")
      slight = described_class.adjustment(finding_with(measurement: 290, threshold: 300), "x")

      expect(severe["magnitude"]).to be > slight["magnitude"]
    end

    it "names the dimension the risk threatens, and dates only when the fix is a date shift" do
      finding = finding_with(measurement: 40, threshold: 300)

      expect(described_class.adjustment(finding, "f:night_noise:alternative_property"))
        .to include("dimension" => "quiet", "direction" => "increase")
      expect(described_class.adjustment(finding, "f:weather_mismatch:shift_dates"))
        .to include("dimension" => "dates")
    end
  end

  describe "a fix that cannot fix anything" do
    it "is not offered at all" do
      # Every alternative in the fixture city is closer to a road than this one already is.
      quiet = forecast(geo: noisy_geo.merge("nearest_major_road_m" => 220))
      risk = quiet["risks"].find { |r| r["risk_type"] == "night_noise" }

      expect(risk["severity"]).to eq("medium")
      expect(risk["mitigations"].first["severity_after"]).to eq("low")

      nothing_better = described_class.swap_property(
        finding_with(measurement: 900, threshold: 300),
        Foresight::Evidence.for_future(future), future
      )
      expect(nothing_better).to be_nil
    end
  end

  describe "the boundary that everyone will want to break" do
    it "writes no future version, and no Future at all" do
      # Comments are stripped first: this pack *talks* about Planning::Simulator at length, because saying why
      # the boundary exists is half of keeping it. What must not appear is a call.
      code = Dir[Rails.root.join("packs/foresight/**/*.rb")].flat_map { |path| File.readlines(path) }
                                                            .grep_v(/^\s*#/).join

      expect(code).not_to match(/future_versions?\b.*(?:create|update|save|insert)/i)
      expect(code).not_to match(/FutureVersionRecord|Elsewhere::Store\.save_future/)
      expect(code).not_to match(/Planning::Simulator/)
    end

    it "returns an adjustment payload for a risk id, and applies nothing" do
      forecast(geo: noisy_geo)
      adjustment = Foresight::Forecasts.mitigation_adjustment(
        risk_id: "#{future["id"]}:night_noise", mitigation_id: "#{future["id"]}:night_noise:alternative_property"
      )

      expect(adjustment).to eq("dimension" => "quiet", "direction" => "increase", "magnitude" => 0.4)
    end

    it "refuses a risk id that names no risk" do
      forecast(geo: noisy_geo)

      expect { Foresight::Forecasts.mitigation_adjustment(risk_id: "#{future["id"]}:crowds", mitigation_id: "x") }
        .to raise_error(ArgumentError, /no crowds risk/)
    end
  end

  def finding_with(measurement:, threshold:)
    Foresight::Rules::Finding.new(risk_type: "night_noise", affected_dimension: "quiet",
                                  claim_kind: "model_inference", statement: "s",
                                  evidence: [{ "source" => "geo" }], measurement: measurement,
                                  threshold: threshold, direction: :below, completeness: 1.0)
  end
end
