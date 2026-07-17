# Private to packs/supply. Records never cross a package boundary — Supply::Catalog hands out value objects.
class DestinationRecord < ActiveRecord::Base
  self.table_name = "destinations"

  has_many :properties, class_name: "PropertyRecord", foreign_key: :destination_id, inverse_of: :destination
end
