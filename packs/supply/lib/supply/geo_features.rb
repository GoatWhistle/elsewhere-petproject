require "date"
require_relative "ors"
require_relative "ohsome"

module Supply
  # Per-property geo features, computed once from the OSM extract. Precomputed, never per request: a
  # generation scores 24 candidates and PostGIS on that path would make every Future wait. Walk isochrones and
  # airport drive time need ORS; without a key they come back absent with a reason, not substituted.
  module GeoFeatures
    RADIUS_M = 500

    # POI density: raw count per km², plus a 0–1 figure as `d/(d+K)` — half-saturation, not a capped ratio.
    # A capped ratio pinned 148 of 408 properties at exactly 1.0 against a 300/km² reference. This curve is
    # monotone over the observed range (0 to 2 028/km²) and never reaches 1. K is fixed, never the corpus
    # median: a moving denominator would rescore every Future ever generated.
    DENSITY_HALF_SATURATION_PER_KM2 = 200.0
    CIRCLE_KM2 = (Math::PI * (RADIUS_M / 1000.0)**2)

    EATING = %w[restaurant cafe bar fast_food pub bakery biergarten food_court].freeze

    # A metric circle in Web Mercator. Mercator stretches distance by 1/cos(latitude), so the radius is
    # divided by it going in and lengths multiplied coming out — exact enough over 500 m, no per-city projection.
    BUFFER_MERC = "ST_Buffer(ST_Transform(pts.geom, 3857), #{RADIUS_M} / COS(RADIANS(ST_Y(pts.geom))))".freeze

    Summary = Struct.new(:properties, :cities, :computed, :ors_calls, :unassessed, keyword_init: true) do
      def to_s
        "#{computed}/#{properties} properties in #{cities} cities · #{ors_calls} ORS calls · " \
          "#{unassessed.map { |field, n| "#{field}:#{n}" }.sort.join(" ")}"
      end
    end

    module_function

    def compute!(city_codes: nil, log: nil)
      summary = Summary.new(properties: 0, cities: 0, computed: 0, ors_calls: 0, unassessed: Hash.new(0))

      DestinationRecord.order(:city_code).then { |s| city_codes ? s.where(city_code: city_codes) : s }.each do |destination|
        rows = measure(destination.city_code)
        next if rows.empty?

        summary.cities += 1
        rows.each { |row| store!(destination, row, summary) }
        log&.call("#{destination.city_code}: #{rows.length} properties")
      end

      summary
    end

    # One query per city, not per property: the same index scans either way, but one round trip instead of sixty.
    def measure(city_code)
      connection.select_all(sanitize(<<~SQL, city_code)).to_a
        WITH pts AS (
          SELECT p.id, ST_SetSRID(ST_MakePoint(p.lon, p.lat), 4326) AS geom
          FROM properties p WHERE p.city_code = %<city>s
        ),
        centre AS (
          SELECT ST_SetSRID(ST_MakePoint(d.lon, d.lat), 4326) AS geom
          FROM destinations d WHERE d.city_code = %<city>s
        )
        SELECT
          pts.id,
          ST_Y(pts.geom) AS lat,
          ST_X(pts.geom) AS lon,
          ROUND(ST_Distance(pts.geom::geography, (SELECT geom FROM centre)::geography)) AS centre_m,
          (SELECT ROUND(MIN(ST_Distance(o.geom::geography, pts.geom::geography)))
             FROM osm_features o WHERE o.city_code = %<city>s AND o.layer = 'coastline') AS sea_m,
          (SELECT COUNT(*) FROM osm_features o
             WHERE o.city_code = %<city>s AND o.layer = 'poi'
               AND ST_DWithin(o.geom::geography, pts.geom::geography, #{RADIUS_M})) AS poi_count,
          (SELECT COUNT(*) FROM osm_features o
             WHERE o.city_code = %<city>s AND o.layer = 'poi'
               AND o.tags->>'amenity' IN (#{EATING.map { |a| "'#{a}'" }.join(", ")})
               AND ST_DWithin(o.geom::geography, pts.geom::geography, #{RADIUS_M})) AS eating_count,
          -- Walkable metres inside the radius. A way that lies wholly inside is measured whole, on the
          -- ellipsoid; only a way that crosses the edge is clipped, in Web Mercator with the latitude scale
          -- taken back out. ST_Intersection returns EMPTY for a short line fully inside a large buffer, so
          -- the containment case cannot be left to it.
          (SELECT ROUND(SUM(
                    CASE WHEN ST_Within(o.geom, ST_Transform(#{BUFFER_MERC}, 4326))
                         THEN ST_Length(o.geom::geography)
                         ELSE ST_Length(ST_Intersection(ST_Transform(o.geom, 3857), #{BUFFER_MERC}))
                              * COS(RADIANS(ST_Y(pts.geom)))
                    END))
             FROM osm_features o WHERE o.city_code = %<city>s AND o.layer = 'walk'
               AND ST_DWithin(o.geom::geography, pts.geom::geography, #{RADIUS_M})) AS walk_m,
          (SELECT jsonb_build_object('m', ROUND(ST_Distance(o.geom::geography, pts.geom::geography)),
                                     'class', o.tags->>'highway')
             FROM osm_features o WHERE o.city_code = %<city>s AND o.layer = 'road'
             ORDER BY o.geom <-> pts.geom LIMIT 1) AS road,
          (SELECT jsonb_build_object('m', ROUND(ST_Distance(o.geom::geography, pts.geom::geography)),
                                     'name', COALESCE(o.tags->>'name', o.tags->>'iata'),
                                     'lat', ST_Y(ST_Centroid(o.geom)), 'lon', ST_X(ST_Centroid(o.geom)))
             FROM osm_features o WHERE o.city_code = %<city>s AND o.layer = 'aerodrome'
             -- an airfield with an IATA code is the one a traveller actually lands at
             ORDER BY (o.tags ? 'iata') DESC, o.geom <-> pts.geom LIMIT 1) AS airport
        FROM pts
      SQL
    end

    def store!(destination, row, summary)
      summary.properties += 1
      unassessed = {}

      sea_m = row["sea_m"]&.to_i
      unassessed["distance_to_sea_m"] = "no coastline within this city's extract" if sea_m.nil?

      road = row["road"] && JSON.parse(row["road"])
      unassessed["nearest_major_road_m"] = "no motorway, trunk, primary or secondary road in the extract" if road.nil?

      airport = row["airport"] && JSON.parse(row["airport"])
      unassessed["airport_distance_m"] = "no aerodrome in this city's extract" if airport.nil?

      walk_m = row["walk_m"]&.to_i
      unassessed["walk_network_m_500m"] = "the walk layer has not been imported for this city" if walk_m.nil?

      poi_count = row["poi_count"].to_i
      per_km2 = (poi_count / CIRCLE_KM2).round(2)

      transfer = airport ? transfer_for(row, airport, summary) : Ors::Answer.new(reason: "no aerodrome to measure from")
      unassessed["airport_transfer_min"] = transfer.reason unless transfer.assessed?

      unassessed.each_key { |field| summary.unassessed[field] += 1 }

      record = PropertyGeoFeatureRecord.find_or_initialize_by(property_id: row["id"])
      record.update!(
        city_code: destination.city_code,
        distance_to_sea_m: sea_m, distance_to_centre_m: row["centre_m"]&.to_i,
        poi_count_500m: poi_count, restaurant_count_500m: row["eating_count"].to_i,
        poi_per_km2: per_km2,
        poi_density: (per_km2 / (per_km2 + DENSITY_HALF_SATURATION_PER_KM2)).round(3),
        walk_network_m_500m: walk_m,
        nearest_major_road_m: road && road["m"].to_i, road_class: road && road["class"],
        airport_distance_m: airport && airport["m"].to_i, airport_name: airport && airport["name"],
        airport_transfer_min: transfer.value,
        unassessed: unassessed, computed_at: Time.now.utc
      )
      summary.computed += 1
    end

    def transfer_for(row, airport, summary)
      return Ors::Answer.new(reason: Ors::NO_KEY) unless Ors.configured?

      summary.ors_calls += 1
      Ors.transfer_minutes(from: { lat: airport["lat"], lon: airport["lon"] },
                           to: { lat: row["lat"], lon: row["lon"] })
    end

    # Everything the pipeline knows about one property, as Supply::Geo hands it out.
    def for_property(property_id)
      record = PropertyGeoFeatureRecord.joins(:property).find_by(properties: { catalogue_id: property_id })
      return nil unless record

      {
        "distance_to_sea_m" => record.distance_to_sea_m,
        "distance_to_centre_m" => record.distance_to_centre_m,
        "poi_density" => record.poi_density&.to_f,
        "poi_count_500m" => record.poi_count_500m,
        "poi_per_km2" => record.poi_per_km2&.to_f,
        "restaurant_count_500m" => record.restaurant_count_500m,
        "walk_network_m_500m" => record.walk_network_m_500m,
        "nearest_major_road_m" => record.nearest_major_road_m,
        "road_class" => record.road_class,
        "airport_distance_m" => record.airport_distance_m,
        "airport_name" => record.airport_name,
        "airport_transfer_min" => record.airport_transfer_min,
        # Absent fields say why, so scoring a missing dimension as neutral is a deliberate act.
        "unassessed" => record.unassessed,
        "computed_at" => record.computed_at&.iso8601,
        "freshness" => "cached"
      }
    end

    # Destination-level geo, computed on demand: one indexed row per city, too cheap to be worth staling.
    def for_destination(city_code)
      row = connection.select_one(sanitize(<<~SQL, city_code))
        WITH centre AS (
          SELECT ST_SetSRID(ST_MakePoint(d.lon, d.lat), 4326) AS geom, d.centre_source
          FROM destinations d WHERE d.city_code = %<city>s
        )
        SELECT
          centre.centre_source,
          (SELECT ROUND(MIN(ST_Distance(o.geom::geography, centre.geom::geography)))
             FROM osm_features o WHERE o.city_code = %<city>s AND o.layer = 'coastline') AS sea_m,
          (SELECT ROUND(ST_Distance(o.geom::geography, centre.geom::geography))
             FROM osm_features o WHERE o.city_code = %<city>s AND o.layer = 'aerodrome'
             ORDER BY (o.tags ? 'iata') DESC, o.geom <-> centre.geom LIMIT 1) AS airport_m,
          (SELECT COALESCE(o.tags->>'name', o.tags->>'iata')
             FROM osm_features o WHERE o.city_code = %<city>s AND o.layer = 'aerodrome'
             ORDER BY (o.tags ? 'iata') DESC, o.geom <-> centre.geom LIMIT 1) AS airport_name
        FROM centre
      SQL
      return nil unless row

      unassessed = {}
      unassessed["distance_to_sea_m"] = "no coastline within this city's extract" if row["sea_m"].nil?
      unassessed["airport_distance_m"] = "no aerodrome in this city's extract" if row["airport_m"].nil?

      {
        "distance_to_sea_m" => row["sea_m"]&.to_i,
        "airport_distance_m" => row["airport_m"]&.to_i,
        "airport_name" => row["airport_name"],
        "centre_source" => row["centre_source"],
        "unassessed" => unassessed,
        "freshness" => "cached"
      }
    end

    # An independent check on the number "sea access" rests on. If the nearest coastline is D metres away, a
    # square of half-width just under D/√2 must hold no coastline and one of half-width 1.2·D must hold some.
    # ohsome answers both from its own copy of OSM, so no geometry endpoint (which answers 403) is needed.
    def verify_sea_distance(property_id)
      features = for_property(property_id)
      distance = features && features["distance_to_sea_m"]
      return { "verifiable" => false, "reason" => "no computed sea distance for #{property_id}" } unless distance

      property = PropertyRecord.find_by!(catalogue_id: property_id)
      inside = Ohsome.coastline_count(**square(property, distance / Math.sqrt(2) * 0.95))
      outside = Ohsome.coastline_count(**square(property, distance * 1.2))

      {
        "verifiable" => inside.assessed? && outside.assessed?,
        "distance_to_sea_m" => distance,
        "coastline_inside_smaller_box" => inside.features, "expected" => 0,
        "coastline_inside_larger_box" => outside.features, "expected_at_least" => 1,
        "agrees" => inside.features&.zero? && outside.features.to_i.positive?,
        "reason" => inside.reason || outside.reason
      }
    end

    def square(property, half_width_m)
      lat = property.lat.to_f
      lon = property.lon.to_f
      d_lat = half_width_m / 111_320.0
      d_lon = half_width_m / (111_320.0 * Math.cos(lat * Math::PI / 180))
      { west: lon - d_lon, south: lat - d_lat, east: lon + d_lon, north: lat + d_lat }
    end

    def sanitize(sql, city_code) = format(sql, city: connection.quote(city_code))
    def connection = ActiveRecord::Base.connection
  end
end
