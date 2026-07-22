require "rails_helper"

RSpec.describe Planning::DnaStore do
  let(:session) do
    Planning::Sessions.create(dream_text: "Вдвоём к тёплому морю, тихо, без машины, до 180000 ₽",
                              origin: "MOW",
                              date_window: { "earliest" => "2026-07-01", "latest" => "2026-07-31" },
                              party: { "adults" => 2 })
  end
  let(:session_id) { session.fetch("id") }

  def dimensions(dna) = dna["elements"].to_h { |element| [element["dimension"], element] }

  describe "it round-trips through PostgreSQL" do
    it "stores the draft as version 1, with its elements" do
      expect(TravelDnaVersionRecord.where(session_id: session_id).count).to eq(1)
      expect(TravelDnaVersionRecord.last.version).to eq(1)
      expect(TravelDnaElementRecord.count).to eq(session.dig("travel_dna", "elements").length)
      expect(TravelDnaElementRecord.pluck(:dimension)).to include("sea_access", "quiet", "car_free")
    end

    it "reads back what it wrote, including targets of every shape" do
      stored = dimensions(described_class.find(session_id))

      expect(stored["sea_access"]["target"]).to eq("high")
      expect(stored["total_budget"]["target"]).to eq(18_000_000)
      expect(stored["car_free"]["target"]).to be(true)
      expect(stored["quiet"]["weight"]).to be_a(Float)
    end
  end

  describe "PATCH is an upsert by dimension" do
    it "edits one element without erasing the rest" do
      before = described_class.find(session_id)["elements"].length

      updated = described_class.update(session_id: session_id,
                                       elements: [{ "dimension" => "quiet", "kind" => "preference",
                                                    "target" => "high", "weight" => 1.0 }])

      expect(updated["elements"].length).to eq(before)
      expect(dimensions(updated)["quiet"]["weight"]).to eq(1.0)
      expect(dimensions(updated)["sea_access"]).to be_present
    end

    it "creates a new version rather than mutating the old one" do
      first = described_class.find(session_id)

      second = described_class.update(session_id: session_id,
                                      elements: [{ "dimension" => "quiet", "kind" => "preference", "target" => "high" }])

      expect(second["version"]).to eq(first["version"] + 1)
      expect(second["id"]).not_to eq(first["id"])
      expect(described_class.read(TravelDnaVersionRecord.find(first["id"]))["elements"])
        .to eq(first["elements"])                      # version 1 is untouched
    end

    it "makes an edited element the user's own word, at full confidence" do
      updated = described_class.update(session_id: session_id,
                                       elements: [{ "dimension" => "comfort", "kind" => "preference",
                                                    "target" => "high" }])

      expect(dimensions(updated)["comfort"]).to include("provenance" => "confirmed", "confidence" => 1.0)
    end

    it "adds a dimension the Dream never mentioned" do
      updated = described_class.update(session_id: session_id,
                                       elements: [{ "dimension" => "nightlife", "kind" => "preference",
                                                    "target" => 0.9 }])

      expect(dimensions(updated)["nightlife"]["target"]).to eq(0.9)
    end
  end

  describe "no cascades" do
    # walkability and transfer_simplicity are inferred from car_free by the parser.
    it "marks an inference whose basis the user removed, instead of re-weighting it" do
      before = dimensions(described_class.find(session_id))
      expect(before["transfer_simplicity"]).to include("provenance" => "inferred")
      weight_before = before["transfer_simplicity"]["weight"]

      after = dimensions(described_class.update(session_id: session_id,
                                                elements: [{ "dimension" => "car_free",
                                                             "kind" => "hard_constraint", "target" => false }]))

      expect(after["transfer_simplicity"]["provenance"]).to eq("default")
      expect(after["transfer_simplicity"]["confidence"]).to eq(0.3)
      # Shown, not silently repaired: the weight is exactly where it was.
      expect(after["transfer_simplicity"]["weight"]).to eq(weight_before)
    end

    it "keeps the orphaned element rather than deleting it — the user did not ask for that either" do
      after = described_class.update(session_id: session_id,
                                     elements: [{ "dimension" => "car_free", "kind" => "hard_constraint",
                                                  "target" => false }])

      expect(dimensions(after)).to have_key("transfer_simplicity")
    end

    it "leaves an inference alone while its basis still stands" do
      after = dimensions(described_class.update(session_id: session_id,
                                                elements: [{ "dimension" => "quiet", "kind" => "preference",
                                                             "target" => "high" }]))

      expect(after["transfer_simplicity"]["provenance"]).to eq("inferred")
    end
  end

  describe "inference never overwrites a statement" do
    it "keeps a user's edit even where an inference would have produced something else" do
      described_class.update(session_id: session_id,
                             elements: [{ "dimension" => "walkability", "kind" => "preference",
                                          "target" => "low", "weight" => 0.1 }])

      # Re-running the merge with the inference still present must not undo the edit.
      after = dimensions(described_class.update(session_id: session_id, elements: []))

      expect(after["walkability"]).to include("provenance" => "confirmed", "target" => "low", "weight" => 0.1)
    end
  end

  describe "answering a clarification" do
    # car_free is only asked about when it was *inferred* — here, from a Dream that is all about walking and
    # never mentions a car. Someone who wants to walk may still rent one.
    let(:walker) do
      Planning::Sessions.create(dream_text: "Хотим всё обходить пешком и вкусно есть", origin: "MOW",
                                date_window: { "earliest" => "2026-07-01", "latest" => "2026-07-31" },
                                party: { "adults" => 2 })
    end

    it "asks about a car only when it inferred one, never when the user said it" do
      expect(session.fetch("clarifications").map { |c| c["id"] }).not_to include("car_free")
      expect(walker.fetch("clarifications").map { |c| c["id"] }).to include("car_free")
    end

    it "removes only the question that was answered" do
      before = walker.fetch("clarifications").map { |c| c["id"] }

      Planning::TravelDna.answer_clarifications(session_id: walker.fetch("id"),
                                                answers: [{ "id" => "car_free", "value" => true }])

      remaining = Planning::Sessions.find(id: walker.fetch("id")).fetch("clarifications").map { |c| c["id"] }
      expect(remaining).to match_array(before - ["car_free"])
      expect(remaining).not_to be_empty
    end

    it "writes the answer into the DNA as the user's own word" do
      Planning::TravelDna.answer_clarifications(session_id: walker.fetch("id"),
                                                answers: [{ "id" => "car_free", "value" => true }])

      expect(dimensions(described_class.find(walker.fetch("id")))["car_free"])
        .to include("provenance" => "confirmed", "confidence" => 1.0, "target" => true)
    end
  end
end
