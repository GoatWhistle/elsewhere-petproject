require "date"
require "time"
require_relative "../../shared/lib/elsewhere/values"
require_relative "supply/http"
require_relative "supply/page_cache"
require_relative "supply/harvest"
require_relative "supply/corpus"
require_relative "supply/osm"
require_relative "supply/ohsome"
require_relative "supply/ors"
require_relative "supply/geo_features"

module Supply
  def self.adapter
    Backend.current
  end

  module FixtureData
    module_function

    def destinations
      [
        Elsewhere::Values::Destination.new(city_code: "AER", name: "Сочи", country: "Россия", coordinates: { "lat" => 43.6, "lon" => 39.7 }, freshness: "fixture"),
        Elsewhere::Values::Destination.new(city_code: "MRV", name: "Кавказские Минеральные Воды", country: "Россия", coordinates: { "lat" => 44.0, "lon" => 43.1 }, freshness: "fixture"),
        Elsewhere::Values::Destination.new(city_code: "LED", name: "Санкт-Петербург", country: "Россия", coordinates: { "lat" => 59.9, "lon" => 30.3 }, freshness: "fixture")
      ]
    end

    def properties
      [
        Elsewhere::Values::Property.new(catalogue_id: "prop-sochi-sea", name: "Морской бриз", city_code: "AER", coordinates: { "lat" => 43.59, "lon" => 39.72 }, rating: 4.7, price_level: 12000, freshness: "fixture"),
        Elsewhere::Values::Property.new(catalogue_id: "prop-sochi-quiet", name: "Тихий двор", city_code: "AER", coordinates: { "lat" => 43.61, "lon" => 39.73 }, rating: 4.4, price_level: 8500, freshness: "fixture"),
        Elsewhere::Values::Property.new(catalogue_id: "prop-mrv-mountain", name: "Горный воздух", city_code: "MRV", coordinates: { "lat" => 44.04, "lon" => 43.08 }, rating: 4.6, price_level: 7000, freshness: "fixture"),
        Elsewhere::Values::Property.new(catalogue_id: "prop-led-city", name: "Невский дом", city_code: "LED", coordinates: { "lat" => 59.93, "lon" => 30.35 }, rating: 4.5, price_level: 9500, freshness: "fixture")
      ]
    end

    def geo
      {
        "prop-sochi-sea" => { "distance_to_sea_m" => 140, "distance_to_centre_m" => 800, "poi_density" => 0.9, "restaurant_count_500m" => 28, "nearest_major_road_m" => 220, "road_class" => "primary", "airport_distance_m" => 28000 },
        "prop-sochi-quiet" => { "distance_to_sea_m" => 650, "distance_to_centre_m" => 1200, "poi_density" => 0.7, "restaurant_count_500m" => 18, "nearest_major_road_m" => 700, "road_class" => "secondary", "airport_distance_m" => 29000 },
        "prop-mrv-mountain" => { "distance_to_sea_m" => nil, "distance_to_centre_m" => 500, "poi_density" => 0.8, "restaurant_count_500m" => 12, "nearest_major_road_m" => 900, "road_class" => "secondary", "airport_distance_m" => 4500 },
        "prop-led-city" => { "distance_to_sea_m" => nil, "distance_to_centre_m" => 100, "poi_density" => 1.0, "restaurant_count_500m" => 40, "nearest_major_road_m" => 90, "road_class" => "primary", "airport_distance_m" => 21000 }
      }
    end

    def climate
      { "AER" => { "temp_mean_c" => 24, "rain_days" => 6, "sea_temp_c" => 23 }, "MRV" => { "temp_mean_c" => 20, "rain_days" => 8, "sea_temp_c" => nil }, "LED" => { "temp_mean_c" => 17, "rain_days" => 10, "sea_temp_c" => nil } }
    end
  end

  # Two sources behind one signature (DEC-005): the fixtures other packages develop against, and the harvested
  # corpus. Neither is a provider call, so both read `cached`, never `live`.
  module Sources
    # `axes` filters and does not label: the contract's Destination schema is closed, so a geography type
    # cannot travel on it and a caller asks for one type at a time (DEC-028).
    module Axes
      module_function

      def match?(geography_type, axes)
        return true if axes.nil? || axes.empty?

        wanted = Array(axes[:geography] || axes["geography"])
        wanted.empty? || wanted.map(&:to_s).include?(geography_type.to_s)
      end
    end

    module Fixtures
      # The three fixture destinations and the geography each stands for. A surprise here is a surprise
      # everywhere, so they do not change.
      GEOGRAPHY = { "AER" => "sea", "MRV" => "mountains", "LED" => "city" }.freeze

      module_function

      def destinations(axes: nil)
        FixtureData.destinations.select { |d| Axes.match?(GEOGRAPHY[d.city_code], axes) }
      end

      def destination(city_code:) = FixtureData.destinations.find { |d| d.city_code == city_code }
      def properties(city_code:, limit: 20) = FixtureData.properties.select { |p| p.city_code == city_code }.first(limit)
      def property(id:) = FixtureData.properties.find { |p| p.catalogue_id == id }
    end

    # Geo is computed from the OSM extract, so it is local data too: `cached`, never `live`.
    module DatabaseGeo
      module_function

      def features(property_id:)
        GeoFeatures.for_property(property_id) ||
          { "freshness" => "cached",
            "unassessed" => { "all" => "no geo features computed for #{property_id} — run Supply::GeoFeatures.compute!" } }
      end

      def features_for_destination(city_code:)
        GeoFeatures.for_destination(city_code) ||
          { "freshness" => "cached", "unassessed" => { "all" => "#{city_code} is not in the corpus" } }
      end
    end

    module FixtureGeo
      module_function

      def features(property_id:) = (FixtureData.geo[property_id] || {}).merge("freshness" => "fixture")
      def features_for_destination(city_code:) = { "airport_distance_m" => 25_000, "freshness" => "fixture" }
    end

    module Database
      module_function

      def destinations(axes: nil)
        scope = DestinationRecord.order(:city_code)
        wanted = Array(axes && (axes[:geography] || axes["geography"])).map(&:to_s)
        scope = scope.where(geography_type: wanted) if wanted.any?
        scope.map { |record| destination_value(record) }
      end

      def destination(city_code:)
        record = DestinationRecord.find_by(city_code: city_code)
        record && destination_value(record)
      end

      # Ordered so "the top few in this city" is the same few every run; row order must not move a Future.
      def properties(city_code:, limit: 20)
        PropertyRecord.where(city_code: city_code)
                      .order(Arel.sql("rating DESC NULLS LAST, review_count DESC NULLS LAST, catalogue_id"))
                      .limit(limit).map { |record| property_value(record) }
      end

      def property(id:)
        record = PropertyRecord.find_by(catalogue_id: id)
        record && property_value(record)
      end

      def destination_value(record)
        Elsewhere::Values::Destination.new(
          city_code: record.city_code, name: record.name, country: record.country,
          coordinates: { "lat" => record.lat.to_f, "lon" => record.lon.to_f }, freshness: "cached"
        )
      end

      def property_value(record)
        Elsewhere::Values::Property.new(
          catalogue_id: record.catalogue_id, name: record.name, city_code: record.city_code,
          coordinates: { "lat" => record.lat.to_f, "lon" => record.lon.to_f },
          rating: record.rating&.to_f,
          # Minor units, as every amount of money in this system is.
          price_level: record.price_level_minor, freshness: "cached"
        )
      end
    end
  end

  module Catalog
    module_function

    def source = Backend.current.catalog
    def destinations(axes: nil) = source.destinations(axes: axes)
    def destination(city_code:) = source.destination(city_code: city_code)
    def properties(city_code:, limit: 20) = source.properties(city_code: city_code, limit: limit)
    def property(id:) = source.property(id: id)
  end

  module Rates
    module_function
    def for(property_id:, check_in:, check_out:, adults:)
      property = Catalog.property(id: property_id)
      nights = (Date.parse(check_out.to_s) - Date.parse(check_in.to_s)).to_i
      seasonal = [6, 7, 8].include?(Date.parse(check_in.to_s).month) ? 1.25 : 0.85
      amount = (property.price_level * seasonal * nights).round
      { "amount" => { "amount_minor" => amount, "currency" => "RUB" }, "basis" => "modeled", "freshness" => "fixture", "calibration" => "harvest:#{property_id}", "handoff_url" => "https://example.invalid/properties/#{property_id}" }
    end
  end

  module Flights
    module_function
    def price(origin:, destination:, depart_on:, return_on:, adults:)
      base = destination == "AER" ? 32000 : (destination == "MRV" ? 25000 : 18000)
      { "amount" => { "amount_minor" => base * adults.to_i, "currency" => "RUB" }, "as_of" => Time.now.utc.iso8601, "freshness" => "fixture", "carrier" => "Fixture Air", "duration_min" => 180, "booking_url" => "https://example.invalid/flights" }
    end
    def around_dates(origin:, destination:, depart_on:, window_days:)
      [{ "date" => depart_on.to_s, "amount" => { "amount_minor" => 32000, "currency" => "RUB" }, "as_of" => Time.now.utc.iso8601, "freshness" => "fixture" }]
    end
  end

  module Geo
    module_function

    def source = Backend.current.geo
    def features(property_id:) = source.features(property_id: property_id)
    def features_for_destination(city_code:) = source.features_for_destination(city_code: city_code)
  end

  module Climate
    module_function
    def normals(city_code:, month:); (FixtureData.climate[city_code] || {}).merge("freshness" => "fixture"); end
    def forecast(city_code:, from:, to:); [{ "date" => from.to_s, "temp_mean_c" => FixtureData.climate.dig(city_code, "temp_mean_c"), "freshness" => "fixture" }]; end
  end

  module Reviews
    Result = Struct.new(:documents, :available, :reason, :freshness, keyword_init: true)
    module_function
    def for_property(property_id:, since: nil); Result.new(documents: [], available: false, reason: "no review source", freshness: "fixture"); end
  end

  module Adapters
    class Fixture
      def catalog; Sources::Fixtures; end
      def geo; Sources::FixtureGeo; end
      def climate; Climate; end
      def rates; Rates; end
      def flights; Flights; end
      def reviews; Reviews; end
    end
    # The seam for Ignav, Open-Meteo and the harvested stores. It keeps the captured corpus so a demo stays
    # deterministic until credentials and imports are configured.
    class Live < Fixture
      # The corpus is harvested and stored locally, so it is available in live mode without a provider call.
      def catalog; Sources::Database; end
      def geo; Sources::DatabaseGeo; end
    end
  end

  module Backend
    module_function
    def current; @current ||= (ENV.fetch("SUPPLY_MODE", "fixture") == "live" ? Adapters::Live.new : Adapters::Fixture.new); end
  end
end
