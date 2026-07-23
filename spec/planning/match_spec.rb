require "rails_helper"

RSpec.describe Planning::Match do
  def dna(*elements) = { "elements" => elements }

  def element(dimension, weight, target: "high", kind: "preference", confidence: 1.0)
    { "dimension" => dimension, "kind" => kind, "target" => target, "weight" => weight,
      "provenance" => "stated", "confidence" => confidence }
  end

  def features(geo: {}, rating: 4.5, temperature: 24.0)
    described_class::Features.new(geo: { "freshness" => "fixture" }.merge(geo), rating: rating,
                                  temperature: temperature)
  end

  describe "the decomposition" do
    let(:scored) do
      described_class.score(dna: dna(element("sea_access", 1.0), element("food_quality", 0.8)),
                            features: features(geo: { "distance_to_sea_m" => 150, "restaurant_count_500m" => 25 }))
    end

    it "adds up exactly to the score it reports" do
      total = scored["contributions"].sum { |c| c["contribution"] }
      weight = scored["contributions"].sum { |c| c["weight"] }

      expect((total / weight).round(4)).to eq(scored["score"])
    end

    it "explains every contribution with the measurement behind it" do
      expect(scored["contributions"].map { |c| c["explanation"] }).to all(be_present)
      expect(scored["contributions"].find { |c| c["dimension"] == "sea_access" }["explanation"]).to include("150")
    end

    it "is identical across runs" do
      again = described_class.score(dna: dna(element("sea_access", 1.0), element("food_quality", 0.8)),
                                    features: features(geo: { "distance_to_sea_m" => 150, "restaurant_count_500m" => 25 }))

      expect(again).to eq(scored)
    end
  end

  describe "normalization is against a fixed ideal" do
    it "does not move when the rest of the candidate set changes" do
      one = described_class.score(dna: dna(element("sea_access", 1.0)),
                                  features: features(geo: { "distance_to_sea_m" => 600 }))

      # Scoring a better candidate afterwards must not restate the first one.
      described_class.score(dna: dna(element("sea_access", 1.0)), features: features(geo: { "distance_to_sea_m" => 10 }))
      again = described_class.score(dna: dna(element("sea_access", 1.0)),
                                    features: features(geo: { "distance_to_sea_m" => 600 }))

      expect(again["score"]).to eq(one["score"])
      expect(one["score"]).to eq(0.8)
    end

    it "lands in the honest band rather than near 100%" do
      full = described_class.score(
        dna: dna(element("sea_access", 1.0), element("quiet", 0.9), element("food_quality", 0.8),
                 element("walkability", 0.7)),
        features: features(geo: { "distance_to_sea_m" => 400, "nearest_major_road_m" => 300,
                                  "road_class" => "primary", "restaurant_count_500m" => 18,
                                  "poi_density" => 0.7, "distance_to_centre_m" => 800 })
      )

      expect(full["score"]).to be_between(0.5, 0.9)
    end
  end

  describe "missing data" do
    it "is reported, never scored as neutral" do
      scored = described_class.score(dna: dna(element("crowds", 0.9, kind: "aversion", target: 0.2),
                                              element("sea_access", 1.0)),
                                     features: features(geo: { "distance_to_sea_m" => 150 }))

      expect(scored["unscored_dimensions"].map { |u| u["dimension"] }).to eq(["crowds"])
      expect(scored["unscored_dimensions"].first["reason"]).to be_present
      expect(scored["contributions"].map { |c| c["dimension"] }).to eq(["sea_access"])
    end

    it "costs coverage, and coverage caps confidence" do
      scored = described_class.score(dna: dna(element("sea_access", 1.0), element("nightlife", 1.0)),
                                     features: features(geo: { "distance_to_sea_m" => 150 }))

      expect(scored["coverage"]).to eq(0.5)
      expect(scored["confidence"]).to eq(0.45)   # 0.5 coverage × 0.9 measured
    end

    it "scores a destination with no coastline as zero rather than unknown" do
      scored = described_class.score(dna: dna(element("sea_access", 1.0)),
                                     features: features(geo: { "distance_to_sea_m" => nil }))

      expect(scored["contributions"].first["satisfaction"]).to eq(0.0)
      expect(scored["unscored_dimensions"]).to be_empty
    end
  end

  describe "an aversion harms rather than merely failing to reward" do
    it "contributes negatively when it is violated" do
      violated = described_class.score(dna: dna(element("crowds", 1.0, kind: "aversion", target: 0.1)),
                                       features: features)
      # crowds has no feature, so inject one through a dimension that does: nature_vs_city as an aversion.
      hated = described_class.score(dna: dna(element("nature_vs_city", 1.0, kind: "aversion", target: 0.1)),
                                    features: features(geo: { "poi_density" => 0.95 }))

      expect(violated["contributions"]).to be_empty
      expect(hated["contributions"].first["contribution"]).to be < 0
      expect(hated["contributions"].first["satisfaction"]).to be_between(0, 1)
    end
  end

  describe "the honesty caps in the table" do
    it "keeps quiet at proxy confidence, because a road distance is not a noise measurement" do
      scored = described_class.score(dna: dna(element("quiet", 1.0)),
                                     features: features(geo: { "nearest_major_road_m" => 220,
                                                               "road_class" => "primary" }))

      expect(scored["contributions"].first["confidence"]).to eq(described_class::PROXY)
      expect(scored["contributions"].first["explanation"]).to include("прокси")
    end

    it "keeps nature_vs_city at proxy confidence, because the green share is not imported" do
      scored = described_class.score(dna: dna(element("nature_vs_city", 1.0, target: 0.2)),
                                     features: features(geo: { "poi_density" => 0.2 }))

      expect(scored["contributions"].first["confidence"]).to eq(described_class::PROXY)
      expect(scored["contributions"].first["explanation"]).to include("зелени не измеряется")
    end
  end

  describe "hard constraints are not scored" do
    it "leaves budget, dates, length and car_free out of the decomposition entirely" do
      scored = described_class.score(
        dna: dna(element("total_budget", nil, kind: "hard_constraint", target: 18_000_000),
                 element("car_free", nil, kind: "hard_constraint", target: true),
                 element("sea_access", 1.0)),
        features: features(geo: { "distance_to_sea_m" => 150 })
      )

      expect(scored["contributions"].map { |c| c["dimension"] }).to eq(["sea_access"])
      expect(scored["unscored_dimensions"]).to be_empty
      expect(scored["coverage"]).to eq(1.0)
    end
  end

  describe "near-equal scores break ties on coverage" do
    it "prefers the Future we know more about when the scores are effectively the same" do
      well_known = { "score" => 0.80, "coverage" => 0.95 }
      barely_known = { "score" => 0.81, "coverage" => 0.50 }

      expect(described_class.better?(well_known, barely_known)).to be(true)
    end

    it "still prefers a clearly better score over better coverage" do
      better = { "score" => 0.88, "coverage" => 0.50 }
      known = { "score" => 0.80, "coverage" => 0.95 }

      expect(described_class.better?(better, known)).to be(true)
    end
  end

  describe "no model produces the number" do
    it "reads the curves from a table and computes the rest here" do
      expect(Planning::Curves::MORE_IS_BETTER["sea_access"]).to eq([[150, 1.0], [600, 0.8], [1500, 0.5],
                                                                    [3000, 0.2], [10_000, 0.1]])
      sources = File.read(Rails.root.join("packs/planning/lib/planning/match.rb"))
      expect(sources).not_to include("AI::Task")
    end
  end
end
