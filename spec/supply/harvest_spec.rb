require "tmpdir"
require "rails_helper"

RSpec.describe Supply::Harvest do
  let(:excerpt) do
    Rails.root.join("packs/supply/fixtures/101hotels/sochi_listing_excerpt.html").read
  end
  let(:city) { { slug: "sochi", city_code: "AER", name: "Сочи", country: "Россия" } }

  # A cache pre-loaded with the captured page: the pass runs end to end and sends nothing, which is also how
  # a second real pass behaves.
  # Every cache-backed example asserts the pass sends nothing; this makes a slip fail loudly rather than
  # quietly harvesting a live site from the test suite.
  def forbid_network!
    allow(Supply::Http).to receive(:get) { raise "a spec must never reach the network" }
  end

  def cache_with(pages)
    forbid_network!
    cache = Supply::PageCache.new(root: Dir.mktmpdir("harvest-spec"))
    pages.each { |url, body| cache.write(url, status: 200, body: body) }
    cache
  end

  describe "the parser, against a real captured response" do
    it "reads every field the catalogue is for" do
      records = Supply::Harvest::Microdata.lodgings(excerpt)

      expect(records.length).to eq(2)
      first = records.first
      expect(first[:source_id]).to eq("657259")
      expect(first[:name]).to eq("Отель Cosmos Stay Le Rond Сочи")
      expect(first[:lat]).to eq("43.655693")
      expect(first[:lon]).to eq("39.658096")
      expect(first[:address]).to include("Ленинградская")
      expect(first[:photos]).to be_present
      expect(Supply::Harvest::Microdata.rating(first)).to eq([9.4, 10])
    end

    it "keeps money as an integer in minor units, decimals included" do
      records = Supply::Harvest::Microdata.lodgings(excerpt)

      expect(Supply::Harvest::Microdata.price_minor(records[0])).to eq(520_000)   # "от 5 200 руб."
      expect(Supply::Harvest::Microdata.price_minor(records[1])).to eq(487_500)   # "от 4 875 руб."
      expect(Supply::Harvest::Microdata.price_minor(price_level_text: "от 3 589,97 руб.")).to eq(358_997)
      expect(Supply::Harvest::Microdata.price_minor(price_level_text: "цена по запросу")).to be_nil
    end
  end

  describe "the pass" do
    it "puts real properties with coordinates in the database" do
      cache = cache_with(Supply::Harvest::Catalogue101.city_url("sochi") => excerpt)

      summary = described_class.run(cities: [city], categories: [], cache: cache)

      expect(summary.properties_written).to eq(2)
      expect(summary.pages_fetched).to eq(0)
      expect(PropertyRecord.where(city_code: "AER").count).to eq(2)
      expect(PropertyRecord.pluck(:lat, :lon)).to all(be_all(&:present?))
      expect(PropertyRecord.find_by(catalogue_id: "101hotels:5716")).to have_attributes(
        name: "Cosmos Сочи Отель", city_code: "AER", price_level_minor: 487_500, price_currency: "RUB"
      )
      expect(DestinationRecord.find_by(city_code: "AER").centre_source).to eq("property_centroid")
    end

    it "never downgrades a centre a better source has already set" do
      cache = cache_with(Supply::Harvest::Catalogue101.city_url("sochi") => excerpt)
      described_class.run(cities: [city], categories: [], cache: cache)

      # A-3 replaces the harvested centroid with the real OSM place node.
      DestinationRecord.find_by(city_code: "AER")
                       .update!(lat: 43.585482, lon: 39.723109, centre_source: "osm_place")
      described_class.run(cities: [city], categories: [], cache: cache)

      expect(DestinationRecord.find_by(city_code: "AER")).to have_attributes(
        centre_source: "osm_place", lat: 43.585482, lon: 39.723109
      )
    end

    it "is re-runnable: a second pass changes nothing and re-requests nothing" do
      cache = cache_with(Supply::Harvest::Catalogue101.city_url("sochi") => excerpt)

      first = described_class.run(cities: [city], categories: [], cache: cache)
      second = described_class.run(cities: [city], categories: [], cache: cache)

      expect(second.pages_fetched).to eq(0)
      expect(second.properties_written).to eq(first.properties_written)
      expect(PropertyRecord.count).to eq(2)
    end

    it "follows the category slices the page itself links, in a stable order" do
      urls = { Supply::Harvest::Catalogue101.city_url("sochi") => excerpt }
      # The three the excerpt itself links, in the order the runner takes them.
      %w[1stars 2stars 3_4_stars].each do |category|
        urls[Supply::Harvest::Catalogue101.category_url("sochi", category)] = excerpt
      end

      summary = described_class.run(cities: [city], categories: %w[1stars 2stars 3_4_stars], cache: cache_with(urls))

      expect(summary.pages_requested).to eq(4)
      expect(summary.pages_from_cache).to eq(4)
      expect(summary.properties_written).to eq(2) # the same two, deduplicated on the source's own id
    end
  end

  describe "politeness" do
    it "never requests a path robots.txt disallows" do
      expect(Supply::Harvest::Catalogue101.allowed?("/main/cities/sochi")).to be(true)
      expect(Supply::Harvest::Catalogue101.allowed?("/search")).to be(false)
      expect(Supply::Harvest::Catalogue101.allowed?("/city/sochi")).to be(false)
    end

    it "stops the pass when the source refuses, instead of trying differently" do
      allow(Supply::Http).to receive(:get).and_return(
        Supply::Http::Response.new(url: "x", status: 429, body: "", headers: {})
      )

      summary = described_class.run(cities: [city, city.merge(slug: "kazan", city_code: "KZN", name: "Казань")],
                                    cache: Supply::PageCache.new(root: Dir.mktmpdir("harvest-refusal")))

      expect(summary.stopped).to include("429")
      expect(summary.refusals).to eq(1)
      expect(Supply::Http).to have_received(:get).once # it did not go on to the second city
      expect(PropertyRecord.count).to eq(0)
    end
  end
end
