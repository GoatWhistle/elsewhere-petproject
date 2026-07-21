require "rails_helper"

RSpec.describe Foresight::Scoring do
  def finding(claim_kind: "derived_metric", measurement:, threshold:, direction: :below, completeness: 1.0)
    Foresight::Rules::Finding.new(risk_type: "walkability", affected_dimension: "walkability",
                                  claim_kind: claim_kind, statement: "s", evidence: [{ "source" => "geo" }],
                                  measurement: measurement, threshold: threshold, direction: direction,
                                  completeness: completeness)
  end

  describe "severity, from the distance to the threshold" do
    it "puts a measurement just past the line in the lowest band" do
      expect(described_class.severity(finding(measurement: 0.34, threshold: 0.35))).to eq("low")
    end

    it "climbs through three bands as the measurement gets worse" do
      # exceedance 0.03 · 0.31 · 0.71 of the threshold
      bands = [0.34, 0.24, 0.10].map { |value| described_class.severity(finding(measurement: value, threshold: 0.35)) }

      expect(bands).to eq(%w[low medium high])
    end

    it "measures the same way when the risk is a measurement being too high" do
      near = finding(measurement: 42_000, threshold: 40_000, direction: :above)
      far = finding(measurement: 90_000, threshold: 40_000, direction: :above)

      expect(described_class.severity(near)).to eq("low")
      expect(described_class.severity(far)).to eq("high")
    end
  end

  describe "confidence, from the kind of claim and the data behind it" do
    it "starts at DEC-030's value for the kind of claim" do
      %w[verified_fact derived_metric model_inference].each do |kind|
        subject = finding(claim_kind: kind, measurement: 0.1, threshold: 0.35)

        expect(described_class.confidence(subject)).to eq(described_class::BY_CLAIM_KIND.fetch(kind))
      end
    end

    it "is lowered by missing data, never raised by anything" do
      whole = finding(measurement: 0.1, threshold: 0.35, completeness: 1.0)
      partial = finding(measurement: 0.1, threshold: 0.35, completeness: 2.0 / 3)

      expect(described_class.confidence(partial)).to be < described_class.confidence(whole)
      expect(described_class.confidence(finding(measurement: 0.1, threshold: 0.35, completeness: 3.0)))
        .to eq(described_class::BY_CLAIM_KIND.fetch("derived_metric"))
    end

    it "never exceeds the ceiling its claim kind sets, however complete the data" do
      inference = finding(claim_kind: "model_inference", measurement: 0.01, threshold: 0.35, completeness: 1.0)

      expect(described_class.confidence(inference)).to eq(0.5)
    end
  end

  describe "the two axes stay separate" do
    # The distinction DEC-030 exists to preserve: these two demand different responses from a traveller and a
    # single blended number would hide exactly that.
    it "tells 'probably fine but severe' apart from 'certainly a minor annoyance'" do
      severe_but_unproven = finding(claim_kind: "model_inference", measurement: 40, threshold: 300, completeness: 1.0)
      minor_but_solid = finding(claim_kind: "derived_metric", measurement: 0.34, threshold: 0.35, completeness: 1.0)

      expect(described_class.severity(severe_but_unproven)).to eq("high")
      expect(described_class.confidence(severe_but_unproven)).to eq(0.5)

      expect(described_class.severity(minor_but_solid)).to eq("low")
      expect(described_class.confidence(minor_but_solid)).to eq(0.75)
    end
  end

  describe "no confidence anywhere is a literal" do
    it "is written down in exactly one place in the pack" do
      sources = Dir[Rails.root.join("packs/foresight/lib/**/*.rb")].reject { |path| path.end_with?("scoring.rb") }
      offenders = sources.select { |path| File.read(path).match?(/"confidence"\s*=>\s*[\d.]+|confidence:\s*[\d.]+/) }

      expect(offenders).to be_empty
    end

    it "is what every risk item actually carries" do
      bundle = Foresight::Evidence::Bundle.new(
        property_id: "p", city_code: "AER", check_in: Date.new(2026, 7, 8), check_out: Date.new(2026, 7, 15),
        months: [7], geo: { "nearest_major_road_m" => 40, "road_class" => "primary" }, climate: {},
        reviews: Supply::Reviews.for_property(property_id: "p"), sources: {}
      )
      found = Foresight::Rules.findings(bundle).first
      item = Foresight::Forecasts.risk_item(found)

      expect(item["confidence"]).to eq(described_class.confidence(found))
      expect(item["severity"]).to eq(described_class.severity(found))
    end
  end
end
