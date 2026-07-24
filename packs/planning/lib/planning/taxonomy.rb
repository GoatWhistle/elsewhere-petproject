module Planning
  # The closed vocabulary the engine speaks (DEC-024). Fixed on purpose: a fixed set is scoreable and
  # explainable, and anything outside it goes to `unmatched_intent` where the user can see it.
  module Taxonomy
    # `more_is_better` — the user wants as much as they can get.
    # `target`        — the user wants a *level*, and overshooting is as wrong as undershooting.
    # `hard`          — disqualifies rather than scores; no curve at all.
    FAMILIES = {
      "sea_access" => :more_is_better, "food_quality" => :more_is_better, "walkability" => :more_is_better,
      "quiet" => :more_is_better, "comfort" => :more_is_better, "transfer_simplicity" => :more_is_better,
      "climate_warm" => :target, "nature_vs_city" => :target, "crowds" => :target, "nightlife" => :target,
      "total_budget" => :hard, "trip_length" => :hard, "dates" => :hard, "car_free" => :hard
    }.freeze

    # `crowds` is the one dimension wanted less of, applied as a penalty rather than a missing bonus.
    KINDS = Hash.new("preference").merge(
      "crowds" => "aversion",
      "total_budget" => "hard_constraint", "trip_length" => "hard_constraint",
      "dates" => "hard_constraint", "car_free" => "hard_constraint"
    ).freeze

    # Only these five may be hard; make "quiet" hard and the result set is empty.
    HARD = %w[total_budget trip_length dates party car_free].freeze

    # What this build can put a number against. `crowds` needs seasonality and popularity, `nightlife` needs a
    # bar layer, and Supply publishes neither, so a Dream of only those two is understood but not scored.
    # Stated here because the parser must know it is leaving the traveller nothing to choose by.
    UNMEASURABLE = %w[crowds nightlife].freeze

    module_function

    def all = FAMILIES.keys
    def family(dimension) = FAMILIES[dimension]
    def kind(dimension) = KINDS[dimension]
    def hard?(dimension) = FAMILIES[dimension] == :hard
    def scored?(dimension) = !hard?(dimension)
    def measurable?(dimension) = scored?(dimension) && !UNMEASURABLE.include?(dimension)
    def known?(dimension) = FAMILIES.key?(dimension)
  end
end
