require "rails_helper"

RSpec.describe Supply::Corpus do
  # The corpus as it actually came out of the harvest — 408 properties over seven destinations. Asserting
  # against the real numbers is the point: a spread that only holds for invented data proves nothing.
  let(:real) do
    described_class.from_snapshot(Rails.root.join("packs/supply/fixtures/corpus_profile.json").read)
  end
  let(:coverage) { described_class.coverage(real) }

  describe "the manifest" do
    it "declares all three geographies, with the reason each destination is in the corpus" do
      types = described_class.manifest.map(&:geography_type)

      expect(types.uniq).to match_array(Supply::Corpus::GEOGRAPHY_TYPES)
      expect(described_class.manifest).to all(have_attributes(note: be_present))
    end

    it "identifies every destination uniquely, by a code a fare can be priced to" do
      expect(described_class.manifest.map(&:city_code).uniq.length).to eq(described_class.manifest.length)
      expect(described_class.manifest.map(&:slug).uniq.length).to eq(described_class.manifest.length)
      expect(described_class.manifest.map(&:city_code)).to all(match(/\A[A-Z]{3}\z/))
    end
  end

  describe "axis coverage" do
    it "has all three geographies present, cities leading" do
      expect(coverage["geography"]).to eq("city" => 3, "mountains" => 2, "sea" => 2)
      expect(coverage["geography"]["city"]).to be >= coverage["geography"]["mountains"]
      expect(coverage["gaps"]).to be_empty
    end

    it "spans cheap to expensive by a wide margin, at property level" do
      price = coverage["price"]

      expect(price["assessed"]).to be(true)
      expect(price["observed"]).to be >= 400
      expect(price["p90_over_p10"]).to be > 10
      expect(price["min"]).to be < 100_000      # under 1 000 ₽ a night exists
      expect(price["max"]).to be > 5_000_000    # so does over 50 000 ₽
    end

    it "offers both ends of the price axis in every destination, not one cheap city and one dear one" do
      expect(coverage["price"]["destinations_offering_both_ends"]).to eq(coverage["destinations"])
    end

    it "spans quiet to busy, and says what that number actually measures" do
      popularity = coverage["popularity"]

      expect(popularity["ratio"]).to be > 3
      expect(popularity["quietest"]).not_to eq(popularity["busiest"])
      expect(popularity["basis"]).to include("proxy, not a crowd measurement")
    end
  end

  describe "when an axis collapses" do
    it "names the missing geography instead of reporting coverage it does not have" do
      only_cities = real.select { |profile| profile.geography_type == "city" }

      gaps = described_class.coverage(only_cities)["gaps"]

      expect(gaps).to include("no mountains destination in the corpus", "no sea destination in the corpus")
    end

    it "reports an unassessed price axis rather than inventing one" do
      priceless = real.map { |profile| profile.dup.tap { |p| p.price_levels_minor = [] } }

      price = described_class.coverage(priceless)["price"]

      expect(price["assessed"]).to be(false)
      expect(price["reason"]).to be_present
    end
  end

  describe "reading the seeded corpus through the interface" do
    before do
      destination = DestinationRecord.create!(city_code: "NOZ", name: "Шерегеш", country: "Россия",
                                              lat: 52.92, lon: 87.98, source: "101hotels",
                                              source_slug: "sheregesh", geography_type: "mountains")
      DestinationRecord.create!(city_code: "LED", name: "Санкт-Петербург", country: "Россия",
                                lat: 59.93, lon: 30.33, source: "101hotels",
                                source_slug: "sankt-peterburg", geography_type: "city")
      PropertyRecord.create!(catalogue_id: "101hotels:1", source: "101hotels", destination: destination,
                             city_code: "NOZ", name: "Шале", lat: 52.93, lon: 87.99, rating: 9.1,
                             rating_scale: 10, review_count: 40, price_level_minor: 650_000,
                             price_currency: "RUB", source_url: "https://example.invalid",
                             harvested_at: Time.current)
    end

    it "filters destinations by geography, so stage 2 can hold its quota" do
      expect(Supply::Sources::Database.destinations(axes: { geography: "mountains" }).map(&:city_code)).to eq(["NOZ"])
      expect(Supply::Sources::Database.destinations(axes: nil).map(&:city_code)).to eq(%w[LED NOZ])
    end

    it "hands out value objects that say the corpus is local data, not a live provider read" do
      property = Supply::Sources::Database.properties(city_code: "NOZ", limit: 5).first

      expect(property).to be_a(Elsewhere::Values::Property)
      expect(property.freshness).to eq("cached")
      expect(property.price_level).to eq(650_000) # minor units
      expect(Supply::Sources::Database.destination(city_code: "NOZ").freshness).to eq("cached")
    end
  end
end
