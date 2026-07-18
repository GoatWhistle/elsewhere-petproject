require "json"
require_relative "http"

module Supply
  # ohsome is used to check the sea distance, not to compute it. The Overpass extract already returns coastline
  # ways as finished LINESTRINGs, and the public instance answers 403 on `/elements/geometry` while
  # `/elements/count` and `/metadata` answer 200. What count can still do is bound our own number from both
  # sides — see `GeoFeatures.verify_sea_distance`.
  module Ohsome
    BASE = "https://api.ohsome.org/v1".freeze

    # `features`, not `count`: a Struct member named `count` would override `Struct#count`.
    Answer = Struct.new(:features, :reason, keyword_init: true) do
      def assessed? = reason.nil?
    end

    module_function

    def base = ENV.fetch("OHSOME_BASE_URL", BASE)

    # bbox is west,south,east,north — ohsome's own order, which is not Overpass's.
    def coastline_count(west:, south:, east:, north:, on: Date.today.prev_month.to_s)
      response = Http.post_form("#{base}/elements/count",
                                { "bboxes" => format("%.6f,%.6f,%.6f,%.6f", west, south, east, north),
                                  "filter" => "natural=coastline and type:way", "time" => on },
                                timeout: 60, min_interval: 2.0)
      return Answer.new(reason: response.error || "HTTP #{response.status}") unless response.ok?

      value = response.json&.dig("result", 0, "value")
      value ? Answer.new(features: value.to_i) : Answer.new(reason: "ohsome returned no result")
    end
  end
end
