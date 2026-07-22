# Private to packs/planning.
class TravelDnaElementRecord < ActiveRecord::Base
  self.table_name = "travel_dna_elements"
  belongs_to :version, class_name: "TravelDnaVersionRecord", foreign_key: :travel_dna_version_id,
                       inverse_of: :elements
end
