module Foresight
  # Severity and confidence, computed rather than chosen (DEC-030). A user reads them the way they read the
  # match percentage, so an invented confidence is no better than an invented score. They are separate axes and
  # must not be collapsed: "probably fine but severe if it happens" and "certainly a minor annoyance" demand
  # different responses, and one blended number hides the difference.
  module Scoring
    # How far past its threshold a measurement sits before the band changes, as a fraction of the threshold —
    # relative, because thresholds are in metres, degrees and densities.
    LOW_BAND_MAX = 0.25
    MEDIUM_BAND_MAX = 0.60

    # Confidence starts from the claim kind (DEC-030) — the only place in this pack where the number is
    # written down, and nothing a rule says can raise it.
    BY_CLAIM_KIND = { "verified_fact" => 0.9, "derived_metric" => 0.75, "model_inference" => 0.5 }.freeze

    module_function

    # Three bands from the distance between the measurement and its threshold.
    def severity(finding)
      exceedance = finding.exceedance.to_f

      case exceedance
      when ..LOW_BAND_MAX then "low"
      when ..MEDIUM_BAND_MAX then "medium"
      else "high"
      end
    end

    # Claim kind × how much of the data the rule actually had: two of three inputs is the same claim with less
    # behind it.
    def confidence(finding)
      base = BY_CLAIM_KIND.fetch(finding.claim_kind)
      (base * completeness(finding)).round(2)
    end

    def completeness(finding)
      value = finding.completeness
      return 1.0 if value.nil?

      value.to_f.clamp(0.0, 1.0)
    end
  end
end
