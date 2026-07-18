class CreatePropertyGeoFeatures < ActiveRecord::Migration[8.1]
  def change
    # Precomputed per property, never per request (A-4). A Future is assembled from 24 candidates; computing
    # sea distance at request time would put PostGIS on the critical path of every generation.
    create_table :property_geo_features, id: :uuid do |t|
      t.references :property, null: false, foreign_key: true, type: :uuid, index: { unique: true }
      t.string :city_code, null: false

      t.integer :distance_to_sea_m
      t.integer :distance_to_centre_m
      t.integer :poi_count_500m
      t.integer :restaurant_count_500m
      t.decimal :poi_per_km2, precision: 10, scale: 2
      t.decimal :poi_density, precision: 4, scale: 3      # normalised against a fixed reference, never the corpus
      t.integer :walk_network_m_500m
      t.integer :nearest_major_road_m
      t.string :road_class
      t.integer :airport_distance_m
      t.string :airport_name
      t.integer :airport_transfer_min                     # OpenRouteService; null when there is no key

      # Why a field above is null. Missing data is reported, never silently scored as neutral (hard rule 5) —
      # "no coastline within the extract" and "we did not look" are different facts and must stay different.
      t.jsonb :unassessed, null: false, default: {}

      t.datetime :computed_at, null: false
      t.timestamps
    end
    add_index :property_geo_features, :city_code
  end
end
