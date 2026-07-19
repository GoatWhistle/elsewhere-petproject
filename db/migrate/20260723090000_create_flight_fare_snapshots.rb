class CreateFlightFareSnapshots < ActiveRecord::Migration[8.1]
  def change
    # A fare is the only paid dependency in this system (DEC-028): about 24 requests per generation, roughly
    # forty generations on the free quota. So every answer is kept, keyed by exactly what was asked.
    create_table :flight_fare_snapshots, id: :uuid do |t|
      t.string :origin, null: false               # IATA *airport* code — city codes are rejected (A-0)
      t.string :destination, null: false
      t.date :depart_on, null: false
      t.date :return_on
      t.integer :adults, null: false, default: 1
      t.string :cabin_class, null: false, default: "economy"

      t.bigint :amount_minor
      t.string :currency, limit: 3
      t.string :price_status                      # the provider's own "verified" / "unverified"
      t.string :carrier
      t.integer :duration_min
      t.integer :stops
      t.string :booking_url
      t.string :provider_itinerary_id

      # What the provider actually had for this route, kept because absence is the interesting part here:
      # A-0 found no direct service into or out of Russia at all.
      t.integer :itineraries
      t.boolean :direct_service
      t.jsonb :unassessed, null: false, default: {}

      t.string :source, null: false, default: "ignav"
      t.datetime :as_of, null: false              # when the fare was observed — mandatory, never derived
      t.timestamps
    end
    add_index :flight_fare_snapshots, %i[origin destination depart_on return_on adults cabin_class],
              unique: true, name: "index_flight_fares_on_query"
  end
end
