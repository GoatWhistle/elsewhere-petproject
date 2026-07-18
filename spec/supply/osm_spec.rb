require "rails_helper"
require "tmpdir"

RSpec.describe Supply::Osm do
  let(:destination) do
    DestinationRecord.create!(city_code: "AER", name: "Сочи", country: "Россия", lat: 43.60, lon: 39.72,
                              source: "101hotels", source_slug: "sochi", geography_type: "sea",
                              centre_source: "property_centroid")
  end

  before do
    PropertyRecord.create!(catalogue_id: "101hotels:1", source: "101hotels", destination: destination,
                           city_code: "AER", name: "У моря", lat: 43.58, lon: 39.71,
                           source_url: "https://example.invalid", harvested_at: Time.current)
    PropertyRecord.create!(catalogue_id: "101hotels:2", source: "101hotels", destination: destination,
                           city_code: "AER", name: "В горах", lat: 43.62, lon: 39.75,
                           source_url: "https://example.invalid", harvested_at: Time.current)
  end

  # Overpass answers, cached the way a real import caches them, so the whole import runs offline.
  def cache_with(layers)
    cache = Supply::PageCache.new(root: Dir.mktmpdir("osm-spec"))
    box = described_class.property_box(destination)
    layers.each do |layer, elements|
      query = described_class.query_for(Supply::Osm::LAYERS.fetch(layer), box)
      url = "#{Supply::Osm::Overpass::ENDPOINT}?data=#{CGI.escape(query)}"
      cache.write(url, status: 200, body: JSON.generate("elements" => elements))
    end
    cache
  end

  let(:place_node) do
    { "type" => "node", "id" => 34_043_670, "lat" => 43.5854823, "lon" => 39.723109,
      "tags" => { "place" => "city", "name" => "Сочи" } }
  end
  let(:restaurant) do
    { "type" => "node", "id" => 1, "lat" => 43.585, "lon" => 39.722, "tags" => { "amenity" => "restaurant" } }
  end
  let(:road) do
    { "type" => "way", "id" => 2, "tags" => { "highway" => "primary", "name" => "Курортный проспект" },
      "geometry" => [{ "lat" => 43.58, "lon" => 39.72 }, { "lat" => 43.59, "lon" => 39.73 }] }
  end

  describe "the extract" do
    it "bounds each city by the properties it actually harvested" do
      box = described_class.property_box(destination)

      expect(box).to eq(south: 43.58, west: 39.71, north: 43.62, east: 39.75)
      expect(described_class.query_for(Supply::Osm::LAYERS.fetch("poi"), box))
        .to include("43.54000,39.67000,43.66000,39.79000") # the POI margin, not a country
    end

    it "stores points and lines as PostGIS geometry, tags and all" do
      summary = described_class.import!(cache: cache_with("poi" => [restaurant], "road" => [road]),
                                        layers: %w[poi road])

      expect(summary.features).to eq(2)
      stored = ActiveRecord::Base.connection.select_all(
        "SELECT layer, osm_type, GeometryType(geom) AS kind, tags->>'highway' AS highway FROM osm_features ORDER BY layer"
      ).to_a
      expect(stored).to eq([
        { "layer" => "poi", "osm_type" => "node", "kind" => "POINT", "highway" => nil },
        { "layer" => "road", "osm_type" => "way", "kind" => "LINESTRING", "highway" => "primary" }
      ])
    end

    it "drops a way it cannot make a line from, rather than coercing one" do
      broken = road.merge("geometry" => [{ "lat" => 43.58, "lon" => 39.72 }])

      summary = described_class.import!(cache: cache_with("road" => [broken]), layers: %w[road])

      expect(summary.features).to eq(0)
    end
  end

  describe "repeatability" do
    it "replaces a city-layer instead of accumulating it" do
      cache = cache_with("poi" => [restaurant])

      described_class.import!(cache: cache, layers: %w[poi])
      described_class.import!(cache: cache, layers: %w[poi])

      expect(ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM osm_features")).to eq(1)
    end

    it "drops what OSM has dropped, which is what makes a second run the same run" do
      described_class.import!(cache: cache_with("poi" => [restaurant, restaurant.merge("id" => 99)]), layers: %w[poi])
      described_class.import!(cache: cache_with("poi" => [restaurant]), layers: %w[poi])

      expect(ActiveRecord::Base.connection.select_values("SELECT osm_id FROM osm_features")).to eq([1])
    end
  end

  describe "the destination centre" do
    it "replaces the harvested centroid with the OSM place node, and records which it is" do
      expect(destination.centre_source).to eq("property_centroid")

      described_class.import!(cache: cache_with("place" => [place_node]), layers: %w[place])

      expect(destination.reload).to have_attributes(centre_source: "osm_place", lat: 43.585482, lon: 39.723109)
    end

    it "leaves the honest centroid alone when OSM has no place node here" do
      described_class.import!(cache: cache_with("place" => []), layers: %w[place])

      expect(destination.reload.centre_source).to eq("property_centroid")
    end
  end

  describe "when there is nothing to bound an extract with" do
    it "skips the city and says so, rather than extracting a region" do
      PropertyRecord.delete_all

      summary = described_class.import!(cache: cache_with({}), layers: %w[poi], log: nil)

      expect(summary.cities).to eq(0)
      expect(summary.errors).to eq(1)
    end
  end
end
