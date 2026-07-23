require "rails_helper"

RSpec.describe Planning::Constraints do
  def dna(*elements) = { "elements" => elements }

  def element(dimension, target, provenance: "stated", kind: "hard_constraint")
    { "dimension" => dimension, "kind" => kind, "target" => target, "provenance" => provenance,
      "confidence" => 1.0 }
  end

  let(:window) { { "earliest" => "2026-07-01", "latest" => "2026-07-31" } }

  describe "only five things may be hard" do
    it "reads the five and nothing else" do
      expect(described_class::ENFORCEABLE).to contain_exactly("total_budget", "dates", "trip_length", "car_free")
    end

    it "never lets a preference become a constraint" do
      set = described_class.from(dna(element("quiet", "high", kind: "preference"),
                                     element("total_budget", 18_000_000)))

      expect(set.budget_minor).to eq(18_000_000)
      expect(set).not_to respond_to(:quiet)
    end
  end

  describe "an inferred hard constraint is not enforced until it is confirmed" do
    it "refuses to disqualify on something the user never said" do
      set = described_class.from(dna(element("car_free", true, provenance: "inferred")))

      expect(set.car_free?).to be(false)
      expect(set.unenforced.first).to include("dimension" => "car_free")
      expect(set.unenforced.first["reason"]).to include("not confirmed")
    end

    it "enforces it once the user confirms it" do
      set = described_class.from(dna(element("car_free", true, provenance: "confirmed")))

      expect(set.car_free?).to be(true)
      expect(set.unenforced).to be_empty
    end
  end

  describe "stage 1: destinations, before anything is scored" do
    let(:destinations) { Supply::Catalog.destinations }

    it "keeps everything when there is no constraint to apply" do
      result = described_class.destinations(destinations, described_class.from(dna))

      expect(result.survivors.length).to eq(destinations.length)
      expect(result.rejections).to be_empty
    end

    it "cuts a destination whose cheapest possible stay already exceeds the budget" do
      # Below the cheapest seven nights anywhere in the fixture corpus.
      set = described_class.from(dna(element("total_budget", 50_000),
                                     element("dates", window)), date_window: window)

      result = described_class.destinations(destinations, set, nights: 7)

      expect(result).to be_empty
      expect(result.rejections.map(&:constraint).uniq).to eq(["total_budget"])
      expect(result.rejections.first.detail).to include("без перелёта")
    end

    it "keeps a destination the budget can reach" do
      set = described_class.from(dna(element("total_budget", 100_000_000),
                                     element("dates", window)), date_window: window)

      expect(described_class.destinations(destinations, set, nights: 7).survivors).to be_present
    end

    it "cuts a destination that cannot be lived in without a car, when the user confirmed they have none" do
      allow(Supply::Geo).to receive(:features).and_return("poi_density" => 0.05)
      set = described_class.from(dna(element("car_free", true, provenance: "confirmed")))

      result = described_class.destinations(destinations, set)

      expect(result).to be_empty
      expect(result.rejections.map(&:constraint).uniq).to eq(["car_free"])
    end
  end

  describe "the final gate on a priced candidate" do
    let(:set) do
      described_class.from(dna(element("total_budget", 20_000_000), element("dates", window),
                               element("trip_length", { "min_nights" => 6, "max_nights" => 8 })),
                           date_window: window)
    end

    def candidate(total:, check_in: "2026-07-08", check_out: "2026-07-15")
      { "check_in" => check_in, "check_out" => check_out,
        "price" => { "total" => { "amount_minor" => total, "currency" => "RUB" } } }
    end

    it "accepts a candidate inside every bound" do
      expect(described_class.violations(candidate(total: 19_000_000), set)).to be_empty
    end

    it "removes one over budget — the budget is the full total, modeled components included" do
      expect(described_class.violations(candidate(total: 20_000_001), set)).to eq(["total_budget"])
    end

    it "removes one outside the date window" do
      violations = described_class.violations(candidate(total: 1, check_in: "2026-06-25", check_out: "2026-07-02"), set)

      expect(violations).to include("dates")
    end

    it "removes one whose length is outside the stated range" do
      expect(described_class.violations(candidate(total: 1, check_in: "2026-07-08", check_out: "2026-07-10"), set))
        .to include("trip_length")
    end
  end

  describe "when nothing survives" do
    it "names the constraint doing the cutting rather than relaxing it silently" do
      set = described_class.from(dna(element("total_budget", 50_000), element("dates", window)),
                                 date_window: window)
      result = described_class.destinations(Supply::Catalog.destinations, set, nights: 7)

      answer = described_class.no_candidates(result.rejections, set)

      expect(answer["unsatisfiable_constraints"]).to eq(["total_budget"])
      expect(answer["reason"]).to include("500 ₽")
      expect(answer["reason"]).to include("Самое дешёвое")
      expect(answer["nearest_alternatives"]).to eq([])
    end
  end
end
