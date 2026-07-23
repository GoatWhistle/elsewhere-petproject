module Planning
  # Natural language into adjustments. The model maps an instruction onto a closed vocabulary and produces no
  # number: the dimension comes from the taxonomy, the direction is one of two words, and the step is
  # DEC-025's, applied here. The fallback is a lexicon over the user's own words.
  module Instructions
    SCHEMA = {
      "type" => "object", "additionalProperties" => false,
      "properties" => {
        "adjustments" => {
          "type" => "array",
          "items" => {
            "type" => "object", "additionalProperties" => false,
            "properties" => { "dimension" => { "type" => "string", "enum" => Taxonomy.all },
                              "direction" => { "type" => "string", "enum" => %w[increase decrease] } },
            "required" => %w[dimension direction]
          }
        },
        "protect_important" => { "type" => "boolean" }
      },
      "required" => %w[adjustments protect_important]
    }.freeze

    # phrase => [dimension, direction]
    PATTERNS = [
      [/дешевл|подешевл|сэконом|бюджетн|снизь\s+цен/i, ["total_budget", "decrease"]],
      [/дорож|комфортн|получше|люкс/i, ["comfort", "increase"]],
      [/тише|потише|спокойн/i, ["quiet", "increase"]],
      [/живе|веселе|ночн\w*\s*жизн|тусов/i, ["nightlife", "increase"]],
      [/природ|зелен|подальше\s+от\s+город/i, ["nature_vs_city", "decrease"]],
      [/город|центр/i, ["nature_vs_city", "increase"]],
      [/ближе\s+к\s+мор|к\s+мор/i, ["sea_access", "increase"]],
      [/пешк|прогул/i, ["walkability", "increase"]]
    ].freeze

    # "…without damaging anything important" is what turns ε into a constraint, so it is read explicitly.
    PROTECT = /без\s+ущерб|не\s+жертв|ничего\s+важн|не\s+ломая/i

    module_function

    def parse(instruction, response: nil)
      outcome = AI::Task.run(task: "map_instruction", input: { "instruction" => instruction.to_s },
                             schema: SCHEMA, fallback: ->(input) { fallback(input["instruction"]) },
                             response: response)
      answer = outcome.value || fallback(instruction)

      [Array(answer["adjustments"]).filter_map { |raw| normalise(raw) }, !!answer["protect_important"], outcome]
    end

    def fallback(instruction)
      text = instruction.to_s
      found = PATTERNS.filter_map do |pattern, (dimension, direction)|
        { "dimension" => dimension, "direction" => direction } if text.match?(pattern)
      end
      { "adjustments" => found.uniq { |a| a["dimension"] }, "protect_important" => text.match?(PROTECT) }
    end

    def normalise(raw)
      dimension = raw["dimension"] || raw[:dimension]
      direction = raw["direction"] || raw[:direction]
      return nil unless Taxonomy.known?(dimension) && %w[increase decrease].include?(direction)

      { "dimension" => dimension, "direction" => direction,
        "magnitude" => raw["magnitude"] || raw[:magnitude] || Adjustments.step_for(dimension) }
    end
  end

  # DEC-025's slider semantics, applied to a Travel DNA. Every number here is the decision's, not a model's.
  module Adjustments
    BUDGET_STEP = 0.08          # cheaper ↔ more comfortable moves the target total by 8%
    LEVEL_STEP = 0.2            # quiet ↔ lively and city ↔ nature move a target by 0.2

    module_function

    def step_for(dimension) = dimension == "total_budget" ? BUDGET_STEP : LEVEL_STEP

    # Returns a new element set; the original is never touched.
    def apply(elements, adjustments)
      adjustments.reduce(elements.map(&:dup)) { |current, adjustment| apply_one(current, adjustment) }
    end

    def apply_one(elements, adjustment)
      dimension = adjustment["dimension"]
      direction = adjustment["direction"]
      step = adjustment["magnitude"].to_f

      elements.map do |element|
        next element unless element["dimension"] == dimension

        element.merge("target" => moved(element, direction, step))
      end.then { |updated| ensure_present(updated, dimension, direction, step) }
    end

    def moved(element, direction, step)
      target = element["target"]
      sign = direction == "increase" ? 1 : -1

      case target
      when Numeric then (target + (sign * step * scale(target))).clamp(lower(element), upper(element))
      when "high" then direction == "increase" ? "high" : "medium"
      when "medium" then direction == "increase" ? "high" : "low"
      when "low" then direction == "increase" ? "medium" : "low"
      else target
      end
    end

    # A budget moves by a percentage of itself; a 0–1 level moves by the step itself.
    def scale(target) = target.abs > 1 ? target.abs : 1.0
    def lower(element) = element["dimension"] == "total_budget" ? 0 : 0.0
    def upper(element) = element["dimension"] == "total_budget" ? Float::INFINITY : 1.0

    # A slider may name a dimension the DNA does not have yet.
    def ensure_present(elements, dimension, direction, step)
      return elements if elements.any? { |element| element["dimension"] == dimension }

      base = Taxonomy.family(dimension) == :more_is_better ? "medium" : 0.5
      elements + [{ "dimension" => dimension, "kind" => Taxonomy.kind(dimension),
                    "target" => moved({ "dimension" => dimension, "target" => base }, direction, step),
                    "weight" => 0.4, "tolerance" => nil, "provenance" => "confirmed", "confidence" => 1.0 }]
    end
  end
end
