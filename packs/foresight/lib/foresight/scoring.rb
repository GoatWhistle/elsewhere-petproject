module Foresight
  # Severity and confidence, computed from the finding rather than chosen by whoever wrote the rule (DEC-030).
  #
  # First version: enough to be honest, not yet enough to be useful. Severity is a single line here, which
  # cannot tell "probably fine but severe" from "certainly a minor annoyance" — C-4 replaces it with bands
  # derived from how far past its threshold the measurement sits.
  module Scoring
    # Confidence starts at what kind of claim is being made, and nothing a rule says can raise it.
    BY_CLAIM_KIND = { "verified_fact" => 0.9, "derived_metric" => 0.75, "model_inference" => 0.5 }.freeze

    module_function

    def severity(finding) = finding.triggered? ? "high" : "low"

    def confidence(finding)
      BY_CLAIM_KIND.fetch(finding.claim_kind).round(2)
    end
  end
end
