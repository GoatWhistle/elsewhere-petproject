class CreateOsmFeatures < ActiveRecord::Migration[8.1]
  def change
    # One table, not one per layer: everything from OSM is an id, some tags and a geometry, always asked the
    # same question. `layer` records what a feature was imported for, so an import is replaced one layer at a
    # time. No ActiveRecord model on purpose — without the postgis adapter gem a model announces "unknown OID"
    # for the geometry column on every boot, and the import writes in bulk while readers use PostGIS functions.
    create_table :osm_features do |t|
      t.string :city_code, null: false      # which corpus extract this came from
      t.string :layer, null: false          # place | aerodrome | poi | road | coastline
      t.string :osm_type, null: false       # node | way | relation
      t.bigint :osm_id, null: false
      t.jsonb :tags, null: false, default: {}
      t.datetime :imported_at, null: false
    end

    reversible do |direction|
      direction.up do
        execute <<~SQL
          ALTER TABLE osm_features ADD COLUMN geom geometry(Geometry, 4326) NOT NULL;
          CREATE INDEX index_osm_features_on_geom ON osm_features USING GIST (geom);
          CREATE INDEX index_osm_features_on_city_and_layer ON osm_features (city_code, layer);
          CREATE UNIQUE INDEX index_osm_features_on_identity
            ON osm_features (city_code, layer, osm_type, osm_id);
        SQL
      end
    end

    # Where a destination's centre came from is already recorded (A-1 wrote "property_centroid"); the OSM
    # import replaces it with "osm_place" when it finds the place node.
  end
end
