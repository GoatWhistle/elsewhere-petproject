require "rails_helper"

RSpec.describe Foresight::Rules do
  # A bundle built by hand, so each rule is judged on numbers the test states outright.
  def bundle(geo: {}, climate: {}, months: [7])
    Foresight::Evidence::Bundle.new(
      property_id: "p", city_code: "AER", check_in: Date.new(2026, 7, 8), check_out: Date.new(2026, 7, 15),
      months: months, geo: geo, climate: climate,
      reviews: Supply::Reviews.for_property(property_id: "p"), sources: {}
    )
  end

  describe "every finding, whatever the rule" do
    let(:findings) do
      described_class.findings(bundle(
        geo: { "nearest_major_road_m" => 40, "road_class" => "primary", "poi_density" => 0.1,
               "restaurant_count_500m" => 1, "airport_distance_m" => 90_000 },
        climate: { 7 => { "temp_mean_c" => 8.0, "rain_days" => 18.0 } }
      ))
    end

    it "carries evidence and a claim kind, always" do
      expect(findings.length).to eq(4)
      findings.each do |finding|
        expect(finding.evidence).to be_present
        expect(finding.evidence.first).to include("source")
        expect(finding.claim_kind).to be_in(%w[verified_fact derived_metric model_inference])
        expect(finding.statement).to be_present
      end
    end

    it "states the measurement and the line it is judged against, so severity can be derived" do
      findings.each do |finding|
        expect(finding.measurement).to be_a(Numeric)
        expect(finding.threshold).to be_a(Numeric)
        expect(finding.direction).to be_in(%i[above below])
        expect(finding.exceedance).to be > 0
      end
    end
  end

  describe "night noise" do
    it "stays a model inference and never claims noise was measured" do
      finding = described_class::NightNoise.call(bundle(geo: { "nearest_major_road_m" => 40, "road_class" => "primary" }))

      expect(finding.claim_kind).to eq("model_inference")
      expect(finding.statement).to include("шум не измерялся")
      expect(finding.evidence.first["source"]).to eq("geo")
    end

    it "judges a trunk road by a further threshold than a residential street" do
      trunk = described_class::NightNoise.call(bundle(geo: { "nearest_major_road_m" => 400, "road_class" => "trunk" }))
      tertiary = described_class::NightNoise.call(bundle(geo: { "nearest_major_road_m" => 400, "road_class" => "tertiary" }))

      expect(trunk).to be_triggered      # 400 m from a trunk road is still audible
      expect(tertiary).not_to be_triggered
    end
  end

  describe "walkability" do
    it "fires when there is little within a walk, and is a derived metric not an inference" do
      finding = described_class::Walkability.call(bundle(geo: { "poi_density" => 0.1, "restaurant_count_500m" => 1 }))

      expect(finding).to be_triggered
      expect(finding.claim_kind).to eq("derived_metric")
      expect(finding.evidence.first["count"]).to eq(1)
    end

    it "does not fire in a dense neighbourhood" do
      finding = described_class::Walkability.call(bundle(geo: { "poi_density" => 0.9, "restaurant_count_500m" => 28 }))

      expect(finding).not_to be_triggered
    end

    it "reports thinner data as less complete rather than as the same claim" do
      without = described_class::Walkability.call(bundle(geo: { "poi_density" => 0.1, "restaurant_count_500m" => 1 }))
      with = described_class::Walkability.call(bundle(geo: { "poi_density" => 0.1, "restaurant_count_500m" => 1,
                                                             "walk_network_m_500m" => 4000 }))

      expect(without.completeness).to be < with.completeness
    end
  end

  describe "weather mismatch" do
    it "fires when a trip meant to be warm is not" do
      finding = described_class::WeatherMismatch.call(bundle(climate: { 7 => { "temp_mean_c" => 8.0 } }))

      expect(finding).to be_triggered
      expect(finding.measurement).to eq(8.0)
      expect(finding.claim_kind).to eq("derived_metric")
    end

    it "says a normal is not a forecast" do
      finding = described_class::WeatherMismatch.call(bundle(climate: { 7 => { "temp_mean_c" => 8.0 } }))

      expect(finding.statement).to include("не прогноз")
    end

    it "inverts for a traveller who did not want heat" do
      hot = { 7 => { "temp_mean_c" => 30.0 } }

      expect(described_class::WeatherMismatch.call(bundle(climate: hot), target: "warm")).not_to be_triggered
      expect(described_class::WeatherMismatch.call(bundle(climate: hot), target: "cool")).to be_triggered
    end

    it "averages the months the stay actually covers, not just the first" do
      finding = described_class::WeatherMismatch.call(
        bundle(climate: { 7 => { "temp_mean_c" => 24.0 }, 8 => { "temp_mean_c" => 14.0 } }, months: [7, 8])
      )

      expect(finding.measurement).to eq(19.0)
    end

    it "adds the sea when there is one, and calls it cold when it is" do
      finding = described_class::WeatherMismatch.call(
        bundle(climate: { 7 => { "temp_mean_c" => 18.0, "rain_days" => 9.0, "sea_temp_c" => 15.0 } })
      )

      expect(finding.statement).to include("для купания это холодно")
      expect(finding.evidence.map { |line| line["excerpt"] }.join).to include("Температура моря")
      expect(finding.completeness).to eq(1.0)
    end
  end

  describe "transfer difficulty" do
    it "measures a long transfer in kilometres when no driving time exists, and says the distance is a floor" do
      finding = described_class::TransferDifficulty.call(bundle(geo: { "airport_distance_m" => 90_000 }))

      expect(finding).to be_triggered
      expect(finding.unit).to eq("m")
      expect(finding.statement).to include("нижняя оценка")
      expect(finding.completeness).to eq(0.5)
    end

    it "prefers a real driving time when ORS has answered, and is more complete for it" do
      finding = described_class::TransferDifficulty.call(
        bundle(geo: { "airport_distance_m" => 30_000, "airport_transfer_min" => 95, "airport_name" => "Пулково" })
      )

      expect(finding).to be_triggered      # 95 minutes, even though 30 km would not have fired
      expect(finding.unit).to eq("min")
      expect(finding.completeness).to eq(1.0)
      expect(finding.evidence.first["excerpt"]).to include("Пулково")
    end
  end

  describe "a rule whose evidence is missing" do
    it "does not run at all, rather than running on nil" do
      findings = described_class.findings(bundle(geo: { "poi_density" => 0.1, "restaurant_count_500m" => 1 }))

      expect(findings.map(&:risk_type)).to eq(%w[walkability])
    end
  end
end
