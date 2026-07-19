class CreateDestinationClimateNormals < ActiveRecord::Migration[8.1]
  def change
    create_table :destination_climate_normals, id: :uuid do |t|
      t.references :destination, null: false, foreign_key: true, type: :uuid
      t.string :city_code, null: false
      t.integer :month, null: false                      # 1..12

      t.decimal :temp_mean_c, precision: 4, scale: 1
      t.decimal :temp_min_c, precision: 4, scale: 1
      t.decimal :temp_max_c, precision: 4, scale: 1
      t.decimal :precipitation_mm, precision: 6, scale: 1
      t.decimal :rain_days, precision: 4, scale: 1       # average count of days ≥ 1 mm, so not an integer
      t.decimal :sea_temp_c, precision: 4, scale: 1

      # Air and sea come from different archives with different depths — 30 years against about three. A single
      # "these are the normals" would paper over a difference the reader needs in order to weigh the number.
      t.integer :air_years_from
      t.integer :air_years_to
      t.integer :sea_years_from
      t.integer :sea_years_to

      t.string :source, null: false
      t.jsonb :unassessed, null: false, default: {}
      t.datetime :computed_at, null: false
      t.timestamps
    end
    add_index :destination_climate_normals, %i[city_code month], unique: true
  end
end
