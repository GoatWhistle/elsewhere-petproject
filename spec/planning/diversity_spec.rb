require "rails_helper"

RSpec.describe Planning::Diversity do
  def assembled(score:, total:, geography:, name: "X", city: "AER")
    destination = Elsewhere::Values::Destination.new(city_code: city, name: name, country: "Россия",
                                                     coordinates: { "lat" => 0, "lon" => 0 }, freshness: "fixture")
    property = Elsewhere::Values::Property.new(catalogue_id: "p-#{name}", name: name, city_code: city,
                                               coordinates: {}, rating: 4.5, price_level: 1, freshness: "fixture")
    {
      "price" => { "total" => { "amount_minor" => total, "currency" => "RUB" } },
      "candidate" => Planning::Candidates::Candidate.new(destination: destination, property: property, geography: geography,
                                   match: { "score" => score, "coverage" => 1.0,
                                            "contributions" => [{ "dimension" => "sea_access", "contribution" => 0.9,
                                                                  "explanation" => "До моря 150 м" }] })
    }
  end

  describe "the three archetypes" do
    let(:priced) do
      [
        assembled(score: 0.85, total: 20_000_000, geography: "sea", name: "Лучший"),
        assembled(score: 0.80, total: 12_000_000, geography: "sea", name: "Дешевле"),
        assembled(score: 0.76, total: 18_000_000, geography: "city", name: "Другой", city: "LED")
      ]
    end
    let(:selection) { described_class.select(priced) }

    it "returns best, cheaper and different, in that order" do
      expect(selection.chosen.map { |a, _| a["candidate"].property.name }).to eq(%w[Лучший Дешевле Другой])
      expect(selection.note).to be_nil
    end

    it "explains each one in the field the contract already has for it" do
      reasons = selection.chosen.map { |_, reason| reason }

      expect(reasons[0]).to include("Лучшее совпадение")
      expect(reasons[1]).to include("Дешевле на 80000")
      expect(reasons[2]).to include("Другая география")
    end
  end

  describe "the quality floors" do
    it "refuses a cheaper option that has fallen more than 0.08 behind" do
      priced = [assembled(score: 0.85, total: 20_000_000, geography: "sea", name: "Лучший"),
                assembled(score: 0.76, total: 9_000_000, geography: "sea", name: "Дёшево и плохо")]

      expect(described_class.select(priced).chosen.length).to eq(1)
      expect(described_class.select(priced).note).to include("Дешевле того же качества не нашлось")
    end

    it "accepts one exactly on the cheaper floor" do
      priced = [assembled(score: 0.85, total: 20_000_000, geography: "sea", name: "Лучший"),
                assembled(score: 0.77, total: 9_000_000, geography: "sea", name: "На пороге")]

      expect(described_class.select(priced).chosen.length).to eq(2)
    end

    it "refuses a different geography that has fallen more than 0.12 behind" do
      priced = [assembled(score: 0.85, total: 20_000_000, geography: "sea", name: "Лучший"),
                assembled(score: 0.72, total: 18_000_000, geography: "city", name: "Другой", city: "LED")]

      selection = described_class.select(priced)
      expect(selection.chosen.length).to eq(1)
      expect(selection.note).to include("не дотягивает до порога 0.73")
    end

    it "requires B to actually be cheaper, not merely comparable" do
      priced = [assembled(score: 0.85, total: 20_000_000, geography: "sea", name: "Лучший"),
                assembled(score: 0.84, total: 21_000_000, geography: "sea", name: "Дороже")]

      expect(described_class.select(priced).chosen.length).to eq(1)
    end
  end

  describe "a deliberately homogeneous set" do
    it "yields two rather than three lookalikes" do
      priced = [assembled(score: 0.85, total: 20_000_000, geography: "sea", name: "A"),
                assembled(score: 0.84, total: 15_000_000, geography: "sea", name: "B"),
                assembled(score: 0.83, total: 16_000_000, geography: "sea", name: "C"),
                assembled(score: 0.82, total: 17_000_000, geography: "sea", name: "D")]

      selection = described_class.select(priced)

      expect(selection.chosen.length).to eq(2)
      expect(selection.note).to include("Другой географии в подборке не осталось")
    end

    it "never pads: no third entry appears just to make three" do
      priced = [assembled(score: 0.85, total: 20_000_000, geography: "sea", name: "A"),
                assembled(score: 0.84, total: 15_000_000, geography: "sea", name: "B")]

      expect(described_class.select(priced).chosen.length).to eq(2)
    end
  end

  describe "the geography order" do
    it "prefers a city over mountains over sea when several would qualify" do
      priced = [assembled(score: 0.85, total: 20_000_000, geography: "sea", name: "Лучший"),
                assembled(score: 0.80, total: 18_000_000, geography: "mountains", name: "Горы", city: "MRV"),
                assembled(score: 0.79, total: 19_000_000, geography: "city", name: "Город", city: "LED")]

      different = described_class.select(priced).chosen.last

      expect(different.first["candidate"].geography).to eq("city")
    end
  end
end
