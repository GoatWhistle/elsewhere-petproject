module Foresight
  # Which risks matter to this traveller. A forecast listing every possible risk is a wall of text; for someone
  # who came for nightlife, a noise finding may not be a risk at all.
  module Relevance
    # A weight at or above this is something the traveller cares about. Weights come from a ranking, so
    # half-way up the scale is the natural line — a constant, not the top N of this particular DNA.
    RELEVANT_WEIGHT = Planning::Taxonomy::WEIGHT_SCALE.begin +
                      (Planning::Taxonomy::WEIGHT_SCALE.end - Planning::Taxonomy::WEIGHT_SCALE.begin) / 2.0

    module_function

    # The DNA behind a future, through Planning's published interface. Unreachable means filter nothing:
    # showing an irrelevant risk is a smaller failure than hiding a relevant one.
    def dna_for(future)
      version_id = future["travel_dna_version_id"]
      return nil unless version_id

      Planning::TravelDna.find(version_id: version_id)
    rescue StandardError
      nil
    end

    def elements(dna) = Array(dna && dna["elements"])

    def element_for(dna, dimension)
      elements(dna).find { |element| element["dimension"] == dimension }
    end

    # Relevant when named with real weight, or named as an aversion or a hard constraint, which need no weight.
    def relevant?(dna, dimension)
      return true if dna.nil?

      element = element_for(dna, dimension)
      return false unless element
      return true if %w[aversion hard_constraint].include?(element["kind"])

      element["weight"].to_f >= RELEVANT_WEIGHT
    end

    def filter(findings, dna)
      findings.select { |finding| relevant?(dna, finding.affected_dimension) }
    end

    # What the traveller asked the climate to be. Without a stated preference the rule keeps its own default.
    def climate_target(dna)
      element = element_for(dna, "climate_warm")
      return "warm" unless element

      element["target"].to_s.empty? ? "warm" : element["target"].to_s
    end
  end
end
