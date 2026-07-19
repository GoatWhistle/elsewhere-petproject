# Private to packs/supply.
class DestinationClimateNormalRecord < ActiveRecord::Base
  self.table_name = "destination_climate_normals"

  belongs_to :destination, class_name: "DestinationRecord", foreign_key: :destination_id
end
