require "rails_helper"

RSpec.describe Planning::DreamParser do
  let(:personas) { JSON.parse(Rails.root.join("spec/fixtures/personas/demo_ru.json").read) }

  describe "the ten personas" do
    it "each get the dimensions their Dream names" do
      missing = personas.filter_map do |persona|
        got = described_class.parse(persona["dream"]).elements.map { |element| element["dimension"] }
        gap = persona["must_include"] - got
        "#{persona["id"]}: #{gap.join(", ")}" if gap.any?
      end

      expect(missing).to be_empty
    end

    it "produce meaningfully different DNA, not ten copies of one" do
      shapes = personas.map do |persona|
        described_class.parse(persona["dream"]).elements.map { |element| element["dimension"] }.sort
      end

      expect(shapes.uniq.length).to eq(10)
    end

    it "give the same answer twice for the same Dream" do
      dream = personas.first["dream"]

      expect(described_class.parse(dream).elements).to eq(described_class.parse(dream).elements)
    end
  end

  describe "provenance and confidence come from the extraction path" do
    let(:parsed) { described_class.parse("Хотим вкусно есть и всё обходить пешком, без машины") }

    def element(dimension) = parsed.elements.find { |item| item["dimension"] == dimension }

    it "marks what the user said in their own words as stated, at full confidence" do
      expect(element("food_quality")).to include("provenance" => "stated", "confidence" => 1.0)
      expect(element("car_free")).to include("provenance" => "stated", "confidence" => 1.0)
    end

    it "marks what we worked out as inferred, and less certain" do
      # "без машины" implies getting around on foot and a simple transfer. It is a claim the user did not make.
      expect(element("transfer_simplicity")).to include("provenance" => "inferred", "confidence" => 0.6)
    end

    it "never lets an inference overwrite something the user stated" do
      # walkability is both stated here and inferrable from car_free; the statement wins.
      expect(element("walkability")).to include("provenance" => "stated", "confidence" => 1.0)
      expect(parsed.elements.count { |item| item["dimension"] == "walkability" }).to eq(1)
    end
  end

  describe "weights come from an order, not from numbers" do
    let(:parsed) { described_class.parse("Вдвоём на неделю к тёплому морю, тихо, до 180000 ₽") }

    it "assigns them by position on a fixed ladder" do
      weighted = parsed.elements.reject { |element| element["weight"].nil? }

      expect(weighted.map { |element| element["weight"] }).to eq(described_class::LADDER.first(weighted.length))
    end

    it "puts everything stated above anything inferred" do
      stated = parsed.elements.select { |e| e["provenance"] == "stated" && e["weight"] }
      inferred = parsed.elements.select { |e| e["provenance"] == "inferred" && e["weight"] }

      expect(inferred).not_to be_empty
      expect(stated.map { |e| e["weight"] }.min).to be > inferred.map { |e| e["weight"] }.max
    end

    it "gives a hard constraint no weight at all — it disqualifies rather than competes" do
      expect(parsed.elements.find { |e| e["dimension"] == "total_budget" }["weight"]).to be_nil
      expect(parsed.elements.find { |e| e["dimension"] == "trip_length" }["weight"]).to be_nil
    end
  end

  describe "the model reads language and never produces a number" do
    it "is never asked for a weight or a confidence" do
      asked_for = described_class::SCHEMA["properties"]["dimensions"]["items"]["properties"].keys

      expect(asked_for).to contain_exactly("dimension", "target", "quote")
      expect(described_class::SCHEMA["properties"].keys).to contain_exactly("dimensions", "ranking", "unmatched")
    end

    it "turns a model's ranking into weights here, deterministically" do
      answer = { "dimensions" => [{ "dimension" => "quiet", "quote" => "тихо" },
                                  { "dimension" => "comfort", "quote" => "комфорт" }],
                 "ranking" => %w[comfort quiet], "unmatched" => [] }

      parsed = described_class.parse("тихо и комфорт", response: ->(_) { answer })

      expect(parsed.elements.map { |e| [e["dimension"], e["weight"]] }).to eq([["comfort", 1.0], ["quiet", 0.9]])
    end
  end

  describe "degradation is surfaced, not acted on" do
    it "reports that the model never answered" do
      parsed = described_class.parse("Вдвоём к морю")

      expect(parsed.degraded).to be(true)
      expect(parsed.degraded_reason).to eq(:model_not_configured)
    end

    it "still reads the Dream, because the fallback quotes the user rather than guessing" do
      parsed = described_class.parse("Вдвоём к тёплому морю, тихо")

      expect(parsed.elements.map { |e| e["dimension"] }).to include("sea_access", "quiet")
      expect(parsed.elements.select { |e| e["provenance"] == "stated" }).to be_present
    end

    it "is not degraded when the model does answer" do
      answer = { "dimensions" => [{ "dimension" => "quiet", "quote" => "тихо" }],
                 "ranking" => ["quiet"], "unmatched" => [] }

      expect(described_class.parse("тихо", response: ->(_) { answer }).degraded).to be(false)
    end
  end

  describe "what the taxonomy cannot hold" do
    it "is surfaced rather than dropped" do
      parsed = described_class.parse("К морю, и обязательно чтобы принимали нашу собаку")

      expect(parsed.unmatched_intent.join(" ")).to include("собак")
    end
  end

  describe "clarifications are a closed list" do
    it "asks only about car_free, party, dates and whether the budget is a ceiling" do
      asked = personas.flat_map { |persona| described_class.parse(persona["dream"]).clarifications }
                      .map { |clarification| clarification["id"] }.uniq

      expect(asked).to all(be_in(%w[car_free party dates budget_hard]))
    end

    it "asks about the budget only when one was named" do
      with = described_class.parse("до 180000 ₽").clarifications.map { |c| c["id"] }
      without = described_class.parse("хочется тепла").clarifications.map { |c| c["id"] }

      expect(with).to include("budget_hard")
      expect(without).not_to include("budget_hard")
    end

    it "does not interrupt about a car the user already ruled out in words" do
      asked = described_class.parse("без машины, всё пешком").clarifications.map { |c| c["id"] }

      expect(asked).not_to include("car_free")
    end
  end
end
