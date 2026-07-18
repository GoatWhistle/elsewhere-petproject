require "json"
require_relative "http"

module Supply
  # OpenRouteService: the only network call in the geo pipeline, for the two things PostGIS cannot answer from
  # an extract — how far you can walk in ten minutes, and how long the airport transfer takes by road.
  # `ORS_API_KEY` is never committed; without it both fields come back absent with a reason, never substituted.
  module Ors
    NO_KEY = "ORS_API_KEY is not set — the walk isochrone and the transfer time were not requested".freeze

    Answer = Struct.new(:value, :reason, keyword_init: true) do
      def assessed? = reason.nil?
    end

    module_function

    def key = ENV["ORS_API_KEY"].to_s.strip
    def configured? = !key.empty?
    def base = ENV.fetch("ORS_BASE_URL", "https://api.openrouteservice.org")

    # Area reachable on foot within `minutes`, in m². A radius answers a different question: an island of
    # hotels across a motorway is 400 m away and forty minutes' walk.
    def walk_isochrone_m2(lat:, lon:, minutes: 10)
      return Answer.new(reason: NO_KEY) unless configured?

      response = Http.post_json("#{base}/v2/isochrones/foot-walking",
                                { "locations" => [[lon.to_f, lat.to_f]], "range" => [minutes * 60],
                                  "range_type" => "time", "attributes" => ["area"] },
                                headers: { "Authorization" => key }, timeout: 60, min_interval: 1.5)
      return Answer.new(reason: "ORS isochrone: #{response.error || "HTTP #{response.status}"}") unless response.ok?

      area = response.json&.dig("features", 0, "properties", "area")
      area ? Answer.new(value: area.round) : Answer.new(reason: "ORS isochrone returned no area")
    end

    # Driving time from the airport to the property, in minutes.
    def transfer_minutes(from:, to:)
      return Answer.new(reason: NO_KEY) unless configured?

      response = Http.post_json("#{base}/v2/matrix/driving-car",
                                { "locations" => [[from[:lon].to_f, from[:lat].to_f], [to[:lon].to_f, to[:lat].to_f]],
                                  "sources" => [0], "destinations" => [1], "metrics" => ["duration"] },
                                headers: { "Authorization" => key }, timeout: 60, min_interval: 1.5)
      return Answer.new(reason: "ORS matrix: #{response.error || "HTTP #{response.status}"}") unless response.ok?

      seconds = response.json&.dig("durations", 0, 0)
      seconds ? Answer.new(value: (seconds / 60.0).round) : Answer.new(reason: "ORS matrix returned no duration")
    end
  end
end
