module Foresight
  # The risk rules: four types, each traced to a measurement that exists. A rule does not decide how bad
  # something is — it produces the measurement, the threshold and the claim kind, and severity and confidence
  # are computed centrally from those (DEC-030).
  module Rules
    # `measurement` is the number, `threshold` the line it is judged against, and `direction` which side of that
    # line is the risky one. Those three are what let severity be derived rather than chosen.
    Finding = Struct.new(:risk_type, :affected_dimension, :claim_kind, :statement, :evidence,
                         :measurement, :threshold, :unit, :direction, :completeness, :inputs,
                         keyword_init: true) do
      # How far past the threshold we are, as a multiple of the threshold. Negative means no risk at all.
      def exceedance
        return nil if measurement.nil? || threshold.nil? || threshold.zero?

        direction == :below ? (threshold - measurement) / threshold.to_f : (measurement - threshold) / threshold.to_f
      end

      def triggered? = exceedance.to_f.positive?
    end

    ALL = [Rules::NightNoise, Rules::Walkability, Rules::WeatherMismatch, Rules::TransferDifficulty].freeze

    module_function

    # Every rule whose evidence exists, fired or not: coverage must tell "found nothing" from "could not run".
    def findings(evidence, dna: nil)
      ALL.filter_map do |rule|
        next unless evidence.available?(rule::RISK_TYPE)

        if rule == WeatherMismatch
          rule.call(evidence, target: Relevance.climate_target(dna))
        else
          rule.call(evidence)
        end
      end
    end
  end
end
