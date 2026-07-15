require "date"
require "bigdecimal"
require "json"
require "securerandom"

module Elsewhere
  module Values
    DIMENSIONS = %w[total_budget trip_length dates sea_access climate_warm quiet food_quality walkability nature_vs_city crowds nightlife comfort car_free transfer_simplicity].freeze
    RISK_TYPES = %w[night_noise crowds walkability weather_mismatch construction transfer_difficulty weak_transport room_location_mismatch seasonal_closure].freeze

    Money = Struct.new(:amount_minor, :currency, keyword_init: true) do
      def initialize(amount_minor:, currency:)
        raise ArgumentError, "amount_minor must be an Integer" unless amount_minor.is_a?(Integer)
        raise ArgumentError, "currency must be a three-letter code" unless currency.to_s.match?(/\A[A-Z]{3}\z/)
        super(amount_minor: amount_minor, currency: currency)
      end
      def self.from_major(amount, currency: "RUB")
        minor = (BigDecimal(amount.to_s) * 100).round(0, BigDecimal::ROUND_HALF_UP).to_i
        new(amount_minor: minor, currency: currency)
      end
      def +(other); assert_currency!(other); self.class.new(amount_minor: amount_minor + other.amount_minor, currency: currency); end
      def -(other); assert_currency!(other); self.class.new(amount_minor: amount_minor - other.amount_minor, currency: currency); end
      def to_h; { "amount_minor" => amount_minor, "currency" => currency }; end
      private
      def assert_currency!(other); raise ArgumentError, "currency mismatch: #{currency} != #{other.currency}" unless currency == other.currency; end
    end
    DateWindow = Struct.new(:from, :to, keyword_init: true)
    Party = Struct.new(:adults, :children, keyword_init: true)
    Coordinates = Struct.new(:lat, :lon, keyword_init: true)
    Destination = Struct.new(:city_code, :name, :country, :coordinates, :freshness, keyword_init: true)
    Property = Struct.new(:catalogue_id, :name, :city_code, :coordinates, :rating, :price_level, :freshness, keyword_init: true)
    Rate = Struct.new(:amount, :basis, :calibration, :handoff_url, :freshness, keyword_init: true)
    TravelLeg = Struct.new(:origin, :destination, :depart_at, :arrive_at, :carrier, :stops, :duration_min, :amount, :as_of, :booking_url, :basis, :freshness, keyword_init: true)
    GeoFeatures = Struct.new(:distance_to_sea_m, :distance_to_centre_m, :poi_density, :restaurant_count_500m, :nearest_major_road_m, :road_class, :airport_distance_m, :freshness, keyword_init: true)
    RiskItem = Struct.new(:id, :risk_type, :severity, :confidence, :claim_kind, :affected_dimension, :statement, :evidence, :mitigations, keyword_init: true)

    def self.uuid; SecureRandom.uuid; end
  end
end
