require "date"
require "time"
require_relative "../../shared/lib/elsewhere/values"
require_relative "../../supply/lib/supply"
require_relative "../../planning/lib/planning"
require_relative "foresight/evidence"
require_relative "foresight/rules/night_noise"
require_relative "foresight/rules/walkability"
require_relative "foresight/rules/weather_mismatch"
require_relative "foresight/rules/transfer_difficulty"
require_relative "foresight/rules"
require_relative "foresight/scoring"
require_relative "foresight/relevance"

module Foresight
  # What could go wrong for this person, stated with its evidence or not stated at all. There is no review
  # source (C-05), so the qualitative layer behind "street noise after 23:00" is gone; what is left is geo and
  # climate, and the rest is reported as unassessed.
  module Forecasts
    # Every type the contract knows. A forecast answers for all of them — with a risk, or with a reason.
    ALL_RISK_TYPES = Elsewhere::Values::RISK_TYPES

    module_function

    def for_future(future_id:)
      future = Planning::Futures.find(future_id: future_id)
      evidence = Evidence.for_future(future)
      dna = Relevance.dna_for(future)

      {
        "future_id" => future_id,
        "generated_at" => Time.now.utc.iso8601,
        "risks" => risks(evidence, dna),
        "coverage" => coverage(evidence)
      }
    end

    # Only rules that fired, and only for dimensions this traveller cares about. A rule that found nothing is
    # silence, not a "low" risk, and `coverage` still reports the type as assessable.
    def risks(evidence, dna)
      findings = Rules.findings(evidence, dna: dna).select(&:triggered?)
      Relevance.filter(findings, dna).map { |finding| risk_item(finding) }
    end

    def risk_item(finding)
      {
        "id" => "risk-#{finding.risk_type}",
        "risk_type" => finding.risk_type,
        "severity" => Scoring.severity(finding),
        "confidence" => Scoring.confidence(finding),
        "claim_kind" => finding.claim_kind,
        "affected_dimension" => finding.affected_dimension,
        "statement" => finding.statement,
        "evidence" => finding.evidence,
        "mitigations" => []
      }
    end

    # Every risk type says whether it was assessed and why not, in the words of whatever refused to answer.
    # Four can only be evidenced by review text, so they always carry Supply's reason for having none.
    def coverage(evidence)
      ALL_RISK_TYPES.map do |risk_type|
        assessed = evidence.available?(risk_type)
        entry = { "risk_type" => risk_type, "assessed" => assessed }
        entry["reason"] = evidence.unavailable_reason(risk_type) unless assessed
        entry
      end
    end

    def mitigation_adjustment(risk_id:, mitigation_id:)
      { "dimension" => "quiet", "direction" => "increase", "magnitude" => 0.25 }
    end
  end
end
