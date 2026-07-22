# Private to packs/planning.
class TravelDnaVersionRecord < ActiveRecord::Base
  self.table_name = "travel_dna_versions"
  has_many :elements, -> { order(:position) }, class_name: "TravelDnaElementRecord",
                                               foreign_key: :travel_dna_version_id, inverse_of: :version,
                                               dependent: :destroy
end
