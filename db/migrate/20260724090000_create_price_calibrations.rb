class CreatePriceCalibrations < ActiveRecord::Migration[8.1]
  def change
    # When a destination is busiest. A judgement, like geography_type, and for the same reason: nothing in the
    # data says a ski resort's peak is January. Declared in the corpus manifest with its reason attached.
    add_column :destinations, :peak_season, :string

    # One row per destination, month and model version — the reference every modeled rate points at.
    #
    # `price_calibrations` was empty while the stub multiplied by a made-up 1.25. It is what makes the answer to
    # "why 12 000 in July" a lookup rather than an opinion.
    create_table :price_calibrations, id: :uuid do |t|
      t.string :city_code, null: false
      t.integer :month, null: false
      t.string :model_version, null: false

      t.decimal :comfort, precision: 4, scale: 3          # 0–1, how much this month suits this destination
      t.decimal :popularity, precision: 4, scale: 3       # 0–1, how busy the destination is at all
      t.decimal :amplitude, precision: 4, scale: 3        # how far the factor may swing here
      t.decimal :seasonal_factor, precision: 4, scale: 3, null: false

      # Every input that produced the factor, so the number can be re-derived by hand.
      t.jsonb :inputs, null: false, default: {}
      t.datetime :computed_at, null: false
      t.timestamps
    end
    add_index :price_calibrations, %i[city_code month model_version], unique: true
  end
end
