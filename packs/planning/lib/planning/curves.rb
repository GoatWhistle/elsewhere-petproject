module Planning
  # The satisfaction curves, as data (DEC-024): one table of breakpoints with linear interpolation, not
  # conditionals scattered through the scorer, so a breakpoint can be argued about and tested on its own.
  # Mirrored in `01_product/mechanics.md`; this constant is the executable source of truth.
  module Curves
    # More is better: the user wants as much of this as they can get.
    # Each entry is [feature value, satisfaction], ascending, interpolated linearly and flat outside the ends.
    MORE_IS_BETTER = {
      # distance to the coastline, metres — nearer is better, so the curve descends
      "sea_access" => [[150, 1.0], [600, 0.8], [1500, 0.5], [3000, 0.2], [10_000, 0.1]],
      # restaurants within 500 m
      "food_quality" => [[3, 0.2], [10, 0.5], [25, 0.8], [60, 1.0]],
      # POIs within a walk
      "walkability" => [[20, 0.2], [60, 0.5], [150, 0.8], [400, 1.0]],
      # property rating, on a 0–5 scale
      "comfort" => [[3.8, 0.3], [4.2, 0.6], [4.6, 0.8], [5.0, 1.0]],
      # airport distance, metres — nearer is better
      "transfer_simplicity" => [[20_000, 0.9], [50_000, 0.7], [100_000, 0.4], [200_000, 0.2]]
    }.freeze

    # `quiet` is its own shape: the distance that matters depends on the class of the road.
    QUIET_BY_ROAD = { "motorway" => 1.0, "trunk" => 1.0, "primary" => 0.9, "secondary" => 0.75,
                      "tertiary" => 0.6 }.freeze
    QUIET_CURVE = [[100, 0.2], [300, 0.4], [700, 0.7], [1500, 0.9]].freeze
    QUIET_RESIDENTIAL = 1.0

    # Target matching: the user wants a *level*, and overshooting is as wrong as undershooting.
    # climate_warm is in °C and has an explicit band; the rest are 0–1 with a tolerance.
    CLIMATE_BAND = { ideal: [22.0, 28.0], half: [18.0, 32.0], floor: [14.0, 34.0] }.freeze
    TOLERANCE = { "nature_vs_city" => 0.15, "nightlife" => 0.2, "crowds" => 0.2 }.freeze

    module_function

    # Descending curves (nearer/smaller is better) are written the same way; interpolate handles both because
    # the satisfaction column carries the direction.
    def interpolate(points, value)
      return points.first.last if value <= points.first.first
      return points.last.last if value >= points.last.first

      points.each_cons(2) do |(x1, y1), (x2, y2)|
        next unless value.between?(x1, x2)

        ratio = (value - x1).to_f / (x2 - x1)
        return (y1 + ((y2 - y1) * ratio)).round(4)
      end
      points.last.last
    end

    def more_is_better(dimension, value)
      points = MORE_IS_BETTER[dimension]
      return nil if points.nil? || value.nil?

      interpolate(points, value.to_f)
    end

    # Distance to a road, weighted by how loud its class is; a residential street scores full marks unmeasured.
    def quiet(metres, road_class)
      return QUIET_RESIDENTIAL if road_class.nil? || !QUIET_BY_ROAD.key?(road_class.to_s)
      return nil if metres.nil?

      base = interpolate(QUIET_CURVE, metres.to_f)
      loudness = QUIET_BY_ROAD.fetch(road_class.to_s)
      # A quieter class lifts the score toward 1 in proportion to how much quieter it is.
      (base + ((1.0 - base) * (1.0 - loudness))).round(4)
    end

    def climate(temperature)
      return nil if temperature.nil?

      value = temperature.to_f
      ideal_low, ideal_high = CLIMATE_BAND[:ideal]
      return 1.0 if value.between?(ideal_low, ideal_high)

      half_low, half_high = CLIMATE_BAND[:half]
      floor_low, floor_high = CLIMATE_BAND[:floor]

      if value < ideal_low
        return interpolate([[floor_low, 0.1], [half_low, 0.5], [ideal_low, 1.0]], value)
      end

      interpolate([[ideal_high, 1.0], [half_high, 0.5], [floor_high, 0.1]], value)
    end

    # satisfaction = 1 − |target − actual|, forgiving inside the tolerance band and falling away outside it.
    def target_match(dimension, target, actual)
      return nil if target.nil? || actual.nil?

      distance = (target.to_f - actual.to_f).abs
      tolerance = TOLERANCE.fetch(dimension, 0.15)
      return 1.0 if distance <= tolerance

      [(1.0 - (distance - tolerance) / (1.0 - tolerance)).round(4), 0.0].max
    end
  end
end
