require_relative "osm/overpass"

module Supply
  # The OSM extract, in PostGIS. Repeatable: every Overpass answer is on disk before it is parsed, and each
  # (city, layer) is replaced as a unit.
  #
  #   bin/rails runner 'puts Supply::Osm.import!(log: ->(l) { puts l })'
  #
  # Nothing here runs at request time; features are precomputed from these tables.
  module Osm
    # What each layer is imported for, which is why bboxes and geometry differ. `out center tags` collapses a
    # POI to one coordinate — an outline turns 13 MB into hundreds. Roads are the one layer fetched `out geom`.
    LAYERS = {
      # The real city centre, replacing the harvest's property centroid.
      "place" => { margin_deg: 0.25, out: "body",
                   selectors: ['node["place"~"^(city|town)$"]'] },
      # Airport distance and transfer difficulty: aerodromes sit well outside a city bbox.
      "aerodrome" => { margin_deg: 0.60, out: "center tags",
                       selectors: ['nwr["aeroway"="aerodrome"]'] },
      # POI and restaurant density around properties.
      "poi" => { margin_deg: 0.04, out: "center tags",
                 selectors: ['nwr["amenity"]', 'nwr["shop"]', 'nwr["tourism"]', 'nwr["leisure"]'] },
      # Road class and proximity — Foresight's night_noise proxy, and walkability inputs.
      "road" => { margin_deg: 0.04, out: "geom tags",
                  selectors: ['way["highway"~"^(motorway|trunk|primary|secondary)$"]'] },
      # Walkability: not the same set as `road` — a motorway is a road and the opposite of walkable.
      "walk" => { margin_deg: 0.04, out: "geom tags",
                  selectors: ['way["highway"~"^(footway|pedestrian|living_street|residential|path|steps|track|unclassified|service)$"]'] },
      # Sea distance, computed locally in PostGIS — ohsome's geometry endpoint is 403 on the public instance.
      "coastline" => { margin_deg: 0.60, out: "geom tags",
                       selectors: ['way["natural"="coastline"]'] }
    }.freeze

    Summary = Struct.new(:cities, :layers, :features, :from_cache, :fetched, :errors, :notes, keyword_init: true) do
      def to_s
        "#{features} features · #{layers} city-layers (#{from_cache} cached, #{fetched} fetched) · " \
          "#{errors} errored#{notes.empty? ? "" : " · #{notes.join("; ")}"}"
      end
    end

    module_function

    def import!(city_codes: nil, layers: LAYERS.keys, cache: PageCache.new, refresh: false, offline: false, log: nil)
      summary = Summary.new(cities: 0, layers: 0, features: 0, from_cache: 0, fetched: 0, errors: 0, notes: [])

      destinations(city_codes).each do |destination|
        box = property_box(destination)
        unless box
          summary.errors += 1
          log&.call("#{destination.city_code}: no harvested property to bound an extract with — skipped")
          next
        end

        summary.cities += 1
        layers.each { |layer| import_layer!(destination, layer, box, cache, refresh, offline, summary, log) }
        adopt_place_centre!(destination, summary, log)
      end

      summary
    end

    def import_layer!(destination, layer, box, cache, refresh, offline, summary, log)
      spec = LAYERS.fetch(layer)
      result = Overpass.query(query_for(spec, box), cache: cache, refresh: refresh, offline: offline)

      if result.error
        summary.errors += 1
        log&.call("#{destination.city_code}/#{layer}: #{result.error}")
        return
      end

      summary.layers += 1
      result.from_cache ? summary.from_cache += 1 : summary.fetched += 1
      written = replace!(destination.city_code, layer, result.elements)
      summary.features += written
      log&.call("#{destination.city_code}/#{layer}: #{written} features#{result.from_cache ? " (cached)" : ""}")
    end

    def query_for(spec, box)
      bbox = Overpass.bbox(box[:south] - spec[:margin_deg], box[:west] - spec[:margin_deg],
                           box[:north] + spec[:margin_deg], box[:east] + spec[:margin_deg])
      body = spec[:selectors].map { |selector| "#{selector}(#{bbox});" }.join
      "[out:json][timeout:300];(#{body});out #{spec[:out]};"
    end

    # A whole (city, layer) is replaced at once: upserting element by element would keep features OSM deleted.
    def replace!(city_code, layer, elements)
      rows = elements.filter_map { |element| row_for(city_code, layer, element) }

      connection.transaction do
        connection.exec_delete(
          "DELETE FROM osm_features WHERE city_code = #{connection.quote(city_code)} AND layer = #{connection.quote(layer)}",
          "osm delete"
        )
        rows.each_slice(500) { |slice| connection.execute(insert_sql(slice)) }
      end
      rows.length
    end

    def row_for(city_code, layer, element)
      geometry = geometry_sql(element)
      return nil unless geometry

      { city_code: city_code, layer: layer, osm_type: element["type"], osm_id: element["id"],
        tags: JSON.generate(element["tags"] || {}), geom: geometry }
    end

    # Point for a coordinate, LineString for a way with geometry. A way under two points is dropped, not coerced.
    def geometry_sql(element)
      if element["geometry"].is_a?(Array)
        points = element["geometry"].filter_map { |p| ("#{p["lon"].to_f} #{p["lat"].to_f}" if p["lat"] && p["lon"]) }
        return nil if points.length < 2

        "ST_SetSRID(ST_GeomFromText('LINESTRING(#{points.join(", ")})'), 4326)"
      else
        centre = element["center"] || element
        return nil unless centre["lat"] && centre["lon"]

        "ST_SetSRID(ST_MakePoint(#{centre["lon"].to_f}, #{centre["lat"].to_f}), 4326)"
      end
    end

    def insert_sql(rows)
      now = connection.quote(Time.now.utc)
      values = rows.map do |row|
        "(#{connection.quote(row[:city_code])}, #{connection.quote(row[:layer])}, " \
          "#{connection.quote(row[:osm_type])}, #{row[:osm_id].to_i}, #{connection.quote(row[:tags])}::jsonb, " \
          "#{now}, #{row[:geom]})"
      end
      "INSERT INTO osm_features (city_code, layer, osm_type, osm_id, tags, imported_at, geom) " \
        "VALUES #{values.join(", ")} ON CONFLICT (city_code, layer, osm_type, osm_id) DO NOTHING"
    end

    # The harvest could only store the property centroid; the place node is the real centre, and the column
    # records which of the two is in there.
    def adopt_place_centre!(destination, summary, log)
      centre = connection.select_one(<<~SQL)
        SELECT ST_Y(geom) AS lat, ST_X(geom) AS lon, tags->>'name' AS name
        FROM osm_features
        WHERE city_code = #{connection.quote(destination.city_code)} AND layer = 'place'
        ORDER BY (tags->>'place' = 'city') DESC,
                 ST_Distance(geom::geography,
                             ST_SetSRID(ST_MakePoint(#{destination.lon.to_f}, #{destination.lat.to_f}), 4326)::geography)
        LIMIT 1
      SQL
      return unless centre

      destination.update!(lat: centre["lat"], lon: centre["lon"], centre_source: "osm_place")
      summary.notes << "#{destination.city_code} centre from OSM place node (#{centre["name"]})"
      log&.call("#{destination.city_code}: centre ← OSM place node #{centre["name"]}")
    end

    def destinations(city_codes)
      scope = DestinationRecord.order(:city_code)
      city_codes ? scope.where(city_code: city_codes) : scope
    end

    # The bbox the harvested properties occupy: a fixed radius would be too small for a spread-out resort.
    def property_box(destination)
      box = PropertyRecord.where(destination_id: destination.id)
                          .pick(Arel.sql("MIN(lat), MIN(lon), MAX(lat), MAX(lon)"))
      return nil if box.nil? || box.first.nil?

      { south: box[0].to_f, west: box[1].to_f, north: box[2].to_f, east: box[3].to_f }
    end

    def connection = ActiveRecord::Base.connection
  end
end
