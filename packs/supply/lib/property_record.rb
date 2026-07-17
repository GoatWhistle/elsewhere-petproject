# Private to packs/supply. See DestinationRecord.
class PropertyRecord < ActiveRecord::Base
  self.table_name = "properties"

  belongs_to :destination, class_name: "DestinationRecord", foreign_key: :destination_id, inverse_of: :properties
end
