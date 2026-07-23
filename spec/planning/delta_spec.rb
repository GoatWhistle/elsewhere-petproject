require "rails_helper"

RSpec.describe Planning::Delta do
  before do
    allow(Supply::Flights).to receive(:price) do |destination:, **|
      { "amount" => { "amount_minor" => { "AER" => 4_000_000, "MRV" => 3_000_000 }.fetch(destination, 3_500_000),
                      "currency" => "RUB" },
        "as_of" => "2026-07-01T00:00:00Z", "carrier" => "Тест", "duration_min" => 150, "stops" => 0,
        "basis" => "observed", "booking_url" => nil }
    end
  end

  let(:session) do
    Planning::Sessions.create(dream_text: "Вдвоём на неделю к морю, тихо, вкусно", origin: "MOW",
                              date_window: { "earliest" => "2026-07-01", "latest" => "2026-07-31" },
                              party: { "adults" => 2 })
  end
  let(:before_future) { Planning::Futures.generate(session_id: session.fetch("id")).fetch("futures").first }
  let(:simulated) { Planning::Simulator.simulate(future_id: before_future.fetch("id"), instruction: "Сделай дешевле") }
  let(:delta) { simulated.fetch("future").fetch("delta") }

  describe "the arithmetic" do
    it "sums its items exactly to the total change, to the minor unit" do
      expect(delta.fetch("items")).to be_present
      expect(delta.fetch("items").sum { |item| item.dig("amount", "amount_minor") })
        .to eq(delta.dig("price_change", "amount_minor"))
    end

    it "is the difference between the two prices it names" do
      expect(delta.dig("price_change", "amount_minor"))
        .to eq(delta.dig("price_after", "amount_minor") - delta.dig("price_before", "amount_minor"))
      expect(delta.dig("price_before", "amount_minor")).to eq(before_future.dig("price", "total", "amount_minor"))
    end

    it "itemizes one entry per thing that actually changed, in a fixed order" do
      descriptions = delta.fetch("items").map { |item| item["description"] }

      expect(descriptions).to be_present
      expect(descriptions.first).to match(/Даты|Направление|Объект/)
      expect(described_class::ORDER).to eq(%i[dates destination property])
    end

    it "names the preference that was traded away" do
      relaxed = delta.fetch("items").filter_map { |item| item["relaxed_dimension"] }

      expect(relaxed).to be_present
      expect(Elsewhere::Values::DIMENSIONS).to include(*relaxed)
    end
  end

  describe "what it says about the match" do
    it "reports the score on both sides and which dimensions moved" do
      expect(delta.fetch("match_before")).to eq(before_future.dig("match", "score"))
      expect(delta.fetch("match_after")).to eq(simulated.dig("future", "match", "score"))
      expect(delta.fetch("dimension_changes")).to be_present
      expect(delta.fetch("dimension_changes").map { |c| c["change"] }.uniq)
        .to all(be_in(%w[improved worsened unchanged]))
    end

    it "reports risks as empty rather than guessing them" do
      # Foresight reads Planning, not the other way round, so a Future cannot ask it what appeared.
      expect(delta.fetch("new_risks")).to eq([])
      expect(delta.fetch("resolved_risks")).to eq([])
    end
  end

  describe "the explanation" do
    it "is prose over numbers that were already computed" do
      expect(delta.fetch("explanation")).to be_present
      expect(delta.fetch("explanation")).to include("совпадение")
    end

    it "falls back to a template rather than to silence when the model is unavailable" do
      sentence = Planning::Explanation.templated("price_change_minor" => -1_037_500, "currency" => "RUB",
                                                 "match_before" => 0.795, "match_after" => 0.4965,
                                                 "changes" => %w[destination property])

      expect(sentence).to include("дешевле на 10375 RUB")
      expect(sentence).to include("0.795 → 0.4965")
    end

    it "asks the model for a sentence and never for a figure" do
      expect(Planning::Explanation::SCHEMA["properties"].keys).to eq(["sentence"])
    end
  end
end
