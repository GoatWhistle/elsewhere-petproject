class AddGeographyTypeToDestinations < ActiveRecord::Migration[8.1]
  def change
    # Which of the three the destination is — the one axis that is a judgement rather than a measurement, so it
    # is declared in the corpus manifest with a reason attached and stored here rather than inferred at read time.
    add_column :destinations, :geography_type, :string
    add_index :destinations, :geography_type
  end
end
