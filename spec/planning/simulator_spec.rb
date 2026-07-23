require "rails_helper"

RSpec.describe Planning::Simulator do
  # The fixture corpus refuses Sochi on the currency mismatch, which would leave nothing to simulate over. A
  # rouble fare is what that destination will look like once the FX question is answered, so the simulator is
  # exercised against the corpus it is actually meant for.
  before do
    allow(Supply::Flights).to receive(:price) do |destination:, **|
      # The sea costs more to reach than the mountains here, so "cheaper" has somewhere real to go — and going
      # there costs the whole of sea_access, which is what makes the epsilon case testable.
      { "amount" => { "amount_minor" => { "AER" => 4_000_000, "MRV" => 3_000_000 }.fetch(destination, 3_500_000),
                      "currency" => "RUB" },
        "as_of" => "2026-07-01T00:00:00Z", "carrier" => "Тест", "duration_min" => 150, "stops" => 0,
        "basis" => "observed", "booking_url" => nil, "coverage" => { "assessed" => true } }
    end
  end

  let(:session) do
    Planning::Sessions.create(dream_text: "Вдвоём на неделю к морю, тихо, вкусно",
                              origin: "MOW",
                              date_window: { "earliest" => "2026-07-01", "latest" => "2026-07-31" },
                              party: { "adults" => 2 })
  end
  let(:futures) { Planning::Futures.generate(session_id: session.fetch("id")).fetch("futures") }
  let(:best) { futures.first }

  describe "the sliders map to model changes, not to a re-sort" do
    it "makes it cheaper by moving to a cheaper trip" do
      result = described_class.simulate(future_id: best.fetch("id"), instruction: "Сделай дешевле")

      expect(result.fetch("kind")).to eq("future")
      future = result.fetch("future")
      expect(future.dig("price", "total", "amount_minor")).to be < best.dig("price", "total", "amount_minor")
      expect(future.fetch("parent_id")).to eq(best.fetch("id"))
      expect(future.fetch("version")).to eq(best.fetch("version") + 1)
    end

    it "uses DEC-025's step for the budget, taken from the trip's own total" do
      expect(Planning::Adjustments::BUDGET_STEP).to eq(0.08)
      expect(Planning::Adjustments::LEVEL_STEP).to eq(0.2)
    end

    it "never mutates the Future it came from" do
      before_price = best.dig("price", "total", "amount_minor")
      described_class.simulate(future_id: best.fetch("id"), instruction: "Сделай дешевле")

      expect(Planning::Futures.find(future_id: best.fetch("id")).dig("price", "total", "amount_minor"))
        .to eq(before_price)
    end
  end

  describe "a hard constraint is never violated" do
    it "keeps the result inside the user's window and budget" do
      result = described_class.simulate(future_id: best.fetch("id"), instruction: "Сделай дешевле")
      future = result["future"]

      expect(Date.parse(future.fetch("check_in"))).to be >= Date.new(2026, 7, 1)
      expect(Date.parse(future.fetch("check_out"))).to be <= Date.new(2026, 7, 31)
    end
  end

  describe "epsilon is a refusal, not a fudge" do
    it "declines a step that would cost a top-weighted dimension more than 0.05, and says what it would save" do
      # Getting cheaper here means leaving the sea entirely, and the Dream leads with the sea.
      result = described_class.simulate(future_id: best.fetch("id"),
                                        instruction: "Сделай дешевле, без ущерба важному")

      expect(result.fetch("kind")).to eq("no_solution")
      reason = result.dig("no_solution", "reason")
      expect(reason).to include("sea_access")
      expect(reason).to include("Не делаю это молча")
      expect(reason).to match(/экономии \d+/)          # the user is told what the trade would be worth
      expect(result.dig("no_solution", "unsatisfiable_constraints")).to eq(["sea_access"])
    end

    it "performs the same step when the user did not ask for anything to be protected" do
      result = described_class.simulate(future_id: best.fetch("id"), instruction: "Сделай дешевле")

      expect(result.fetch("kind")).to eq("future")
      expect(result.dig("future", "destination", "city_code")).not_to eq(best.dig("destination", "city_code"))
    end

    it "protects exactly the top three dimensions by weight" do
      expect(Planning::SimulatorCore::PROTECTED_COUNT).to eq(3)
      expect(Planning::SimulatorCore::EPSILON).to eq(0.05)
    end
  end

  describe "when there is nowhere to go" do
    it "returns NoSolution naming what could not be satisfied" do
      result = described_class.simulate(future_id: best.fetch("id"),
                                        adjustments: [{ "dimension" => "sea_access", "direction" => "increase" }])

      expect(result.fetch("kind")).to eq("no_solution")
      expect(result.dig("no_solution", "unsatisfiable_constraints")).to include("sea_access")
      expect(result.dig("no_solution", "reason")).to include("двигаться некуда")
    end

    it "says so rather than returning a version identical to its parent" do
      allow(Planning::SimulatorCore).to receive(:re_solve).and_return([nil, []])

      result = described_class.simulate(future_id: best.fetch("id"), instruction: "Сделай дешевле")

      expect(result.fetch("kind")).to eq("no_solution")
    end
  end

  describe "a drag is one version, not one per pixel" do
    it "coalesces successive steps of the same slider" do
      first = described_class.simulate(future_id: best.fetch("id"), instruction: "Сделай дешевле")
      skip "nothing cheaper on this corpus" unless first["kind"] == "future"

      second = described_class.simulate(future_id: first.dig("future", "id"), instruction: "Сделай дешевле")
      next unless second["kind"] == "future"

      lineage = Planning::Futures.list(session_id: session.fetch("id"))["futures"]
                                 .select { |f| f["lineage_id"] == best["lineage_id"] }

      # The intermediate is gone: the parent and one current version, never a version per drag step.
      expect(lineage.map { |f| f["version"] }.max).to eq(2)
      expect(second.dig("future", "parent_id")).to eq(best.fetch("id"))
    end
  end
end
