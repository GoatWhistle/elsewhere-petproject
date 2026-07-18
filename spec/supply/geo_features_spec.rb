require "rails_helper"

RSpec.describe Supply::GeoFeatures do
  let(:destination) do
    DestinationRecord.create!(city_code: "AER", name: "Сочи", country: "Россия",
                              lat: 43.585482, lon: 39.723109, source: "101hotels",
                              source_slug: "sochi", geography_type: "sea", centre_source: "osm_place")
  end
  let!(:seafront) do
    PropertyRecord.create!(catalogue_id: "101hotels:sea", source: "101hotels", destination: destination,
                           city_code: "AER", name: "У самого моря", lat: 43.5800, lon: 39.7200,
                           source_url: "https://example.invalid", harvested_at: Time.current)
  end

  # osm_features has no ActiveRecord model on purpose, so the spec writes it the way the importer does.
  def osm(layer, osm_id, geometry, tags = {})
    ActiveRecord::Base.connection.execute(<<~SQL)
      INSERT INTO osm_features (city_code, layer, osm_type, osm_id, tags, imported_at, geom)
      VALUES ('AER', '#{layer}', '#{geometry.start_with?("ST_MakePoint") ? "node" : "way"}', #{osm_id},
              '#{tags.to_json}'::jsonb, NOW(), ST_SetSRID(#{geometry}, 4326))
    SQL
  end

  def point(lat, lon) = "ST_MakePoint(#{lon}, #{lat})"
  def line(*coords) = "ST_GeomFromText('LINESTRING(#{coords.each_slice(2).map { |lat, lon| "#{lon} #{lat}" }.join(", ")})')"

  def features = described_class.for_property("101hotels:sea")

  describe "what it computes locally" do
    before do
      osm("coastline", 1, line(43.5790, 39.7190, 43.5790, 39.7250))       # ~110 m south of the property
      osm("poi", 10, point(43.5801, 39.7201), "amenity" => "restaurant")
      osm("poi", 11, point(43.5802, 39.7202), "amenity" => "cafe")
      osm("poi", 12, point(43.5803, 39.7203), "shop" => "bakery")
      osm("poi", 13, point(43.6500, 39.8000), "amenity" => "restaurant")  # 8 km away — outside the radius
      osm("road", 20, line(43.5810, 39.7190, 43.5810, 39.7250), "highway" => "primary", "name" => "Курортный")
      osm("walk", 30, line(43.5800, 39.7200, 43.5805, 39.7200), "highway" => "footway")
      osm("aerodrome", 40, point(43.4499, 39.9566), "aeroway" => "aerodrome", "iata" => "AER", "name" => "Сочи")
      described_class.compute!
    end

    it "measures the sea, the centre and the nearest major road with its class" do
      expect(features["distance_to_sea_m"]).to be_within(30).of(111)
      expect(features["distance_to_centre_m"]).to be_within(200).of(700)
      expect(features["nearest_major_road_m"]).to be_within(30).of(111)
      expect(features["road_class"]).to eq("primary")
    end

    it "counts POIs inside the radius and no further, and separates the ones you eat in" do
      expect(features["poi_count_500m"]).to eq(3)      # the 8 km restaurant is not one of them
      expect(features["restaurant_count_500m"]).to eq(2)
      expect(features["poi_per_km2"]).to be_within(0.1).of(3 / (Math::PI * 0.25))
    end

    it "normalises density on a fixed curve that never saturates, and never against the corpus" do
      density = features["poi_per_km2"]
      k = described_class::DENSITY_HALF_SATURATION_PER_KM2

      expect(features["poi_density"]).to eq((density / (density + k)).round(3))
      expect(k).to eq(200.0)
      expect(features["poi_density"]).to be < 1.0
    end

    it "prefers the aerodrome a traveller actually lands at" do
      osm("aerodrome", 41, point(43.5810, 39.7210), "aeroway" => "aerodrome", "name" => "Аэроклуб")
      described_class.compute!

      expect(features["airport_name"]).to eq("Сочи")   # the one with an IATA code, 15 km away
      expect(features["airport_distance_m"]).to be > 10_000
    end

    it "sums only the walkable metres that fall inside the radius" do
      expect(features["walk_network_m_500m"]).to be_within(10).of(56)
    end
  end

  describe "what it cannot compute" do
    before { described_class.compute! }

    it "reports each absent field with its own reason rather than a neutral value" do
      expect(features["distance_to_sea_m"]).to be_nil
      expect(features["unassessed"]).to include(
        "distance_to_sea_m" => "no coastline within this city's extract",
        "nearest_major_road_m" => a_string_including("no motorway"),
        "airport_distance_m" => "no aerodrome in this city's extract"
      )
    end

    it "says the transfer time was never requested, instead of estimating one" do
      expect(features["airport_transfer_min"]).to be_nil
      expect(features["unassessed"]["airport_transfer_min"]).to be_present
    end

    it "answers for a property it has never computed without pretending otherwise" do
      answer = Supply::Sources::DatabaseGeo.features(property_id: "101hotels:never-seen")

      expect(answer["freshness"]).to eq("cached")
      expect(answer["unassessed"]["all"]).to include("no geo features computed")
    end
  end

  describe "without an ORS key" do
    it "asks for nothing and says why" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("ORS_API_KEY").and_return("")
      expect(Supply::Http).not_to receive(:post_json)

      expect(Supply::Ors.walk_isochrone_m2(lat: 43.58, lon: 39.72).reason).to include("ORS_API_KEY is not set")
      expect(Supply::Ors.transfer_minutes(from: { lat: 1, lon: 1 }, to: { lat: 2, lon: 2 }).reason)
        .to include("ORS_API_KEY is not set")
    end
  end

  describe "destination-level geo" do
    before do
      osm("aerodrome", 40, point(43.4499, 39.9566), "aeroway" => "aerodrome", "iata" => "AER", "name" => "Сочи")
      destination
    end

    it "measures from the centre and says where that centre came from" do
      answer = Supply::Sources::DatabaseGeo.features_for_destination(city_code: "AER")

      expect(answer["airport_distance_m"]).to be_within(3_000).of(23_000)
      expect(answer["centre_source"]).to eq("osm_place")
      expect(answer["unassessed"]).to include("distance_to_sea_m")
    end
  end
end
