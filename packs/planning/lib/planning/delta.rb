require_relative "assembly"

module Planning
  # What changed, itemized, and why. Sequential re-pricing: a global re-solve changes several things at once
  # and attributing a joint change afterwards is order-dependent, so the parts would not sum. The order is
  # fixed, the trip is re-priced after each step, and each difference is one item. No number here comes from a
  # model — `AI::Task` is handed the arithmetic and asked only for a sentence.
  module Delta
    # Dates first, then where, then which property. Any fixed order works; what matters is that it is fixed.
    ORDER = %i[dates destination property].freeze

    module_function

    def between(parent, child, requested = [])
      before = parent.dig("price", "total", "amount_minor")
      after = child.dig("price", "total", "amount_minor")
      currency = child.dig("price", "total", "currency")

      {
        "from_future_id" => parent["id"],
        "price_before" => parent.dig("price", "total"), "price_after" => child.dig("price", "total"),
        "price_change" => { "amount_minor" => after - before, "currency" => currency },
        "items" => items(parent, child, currency, requested),
        "match_before" => parent.dig("match", "score"), "match_after" => child.dig("match", "score"),
        "dimension_changes" => dimension_changes(parent, child),
        # Foresight reads Planning and not the reverse, so a Future cannot ask what risks appeared; the client
        # fetches the forecast per version.
        "new_risks" => [], "resolved_risks" => [],
        "explanation" => Explanation.for(parent, child, requested)
      }
    end

    # One item per step. The last lands on the child's own price, so items sum to the total change exactly,
    # by construction rather than rounding.
    def items(parent, child, currency, requested)
      steps = changed_steps(parent, child)
      return [] if steps.empty?

      running = parent.dig("price", "total", "amount_minor")
      relaxed = relaxed_dimension(parent, child, requested)

      steps.each_with_index.map do |step, index|
        price = index == steps.length - 1 ? child.dig("price", "total", "amount_minor") : repriced(parent, child, steps.first(index + 1))
        amount = price - running
        running = price

        { "description" => describe(step, parent, child), "amount" => { "amount_minor" => amount, "currency" => currency },
          "relaxed_dimension" => index == steps.length - 1 ? relaxed : nil }
      end
    end

    def changed_steps(parent, child)
      ORDER.select do |step|
        case step
        when :dates then parent["check_in"] != child["check_in"] || parent["check_out"] != child["check_out"]
        when :destination then parent.dig("destination", "city_code") != child.dig("destination", "city_code")
        when :property then parent.dig("accommodation", "catalogue_id") != child.dig("accommodation", "catalogue_id")
        end
      end
    end

    # Re-price with only the first `steps` applied; a fare is reused when destination and dates are unchanged.
    def repriced(parent, child, steps)
      check_in = steps.include?(:dates) ? child["check_in"] : parent["check_in"]
      check_out = steps.include?(:dates) ? child["check_out"] : parent["check_out"]
      city = steps.include?(:destination) ? child.dig("destination", "city_code") : parent.dig("destination", "city_code")
      property = steps.include?(:property) || steps.include?(:destination) ? child.dig("accommodation", "catalogue_id") : parent.dig("accommodation", "catalogue_id")

      rate = Supply::Rates.for(property_id: property, check_in: check_in, check_out: check_out, adults: 2)
      fare = Supply::Flights.price(origin: parent.dig("logistics", "outbound", "origin"), destination: city,
                                   depart_on: check_in, return_on: check_out, adults: 2)
      return parent.dig("price", "total", "amount_minor") unless rate["amount"] && fare["amount"]

      rate["amount"]["amount_minor"] + fare["amount"]["amount_minor"]
    end

    def describe(step, parent, child)
      case step
      when :dates then "Даты: #{parent["check_in"]} → #{child["check_in"]}"
      when :destination then "Направление: #{parent.dig("destination", "name")} → #{child.dig("destination", "name")}"
      when :property then "Объект: #{parent.dig("accommodation", "name")} → #{child.dig("accommodation", "name")}"
      end
    end

    def dimension_changes(parent, child)
      before = satisfaction_map(parent)
      after = satisfaction_map(child)

      (before.keys | after.keys).filter_map do |dimension|
        was = before[dimension]
        now = after[dimension]
        next if was.nil? || now.nil?

        change = if (now - was).abs < 0.005 then "unchanged"
                 elsif now > was then "improved"
                 else "worsened"
                 end
        { "dimension" => dimension, "change" => change }
      end
    end

    def satisfaction_map(future)
      Array(future.dig("match", "contributions")).to_h { |c| [c["dimension"], c["satisfaction"]] }
    end

    # Which preference was traded away: the lowest-weight dimension that actually got worse.
    def relaxed_dimension(parent, child, _requested)
      before = satisfaction_map(parent)
      after = satisfaction_map(child)
      weights = Array(child.dig("match", "contributions")).to_h { |c| [c["dimension"], c["weight"]] }

      worsened = before.keys.select { |dimension| after[dimension] && after[dimension] < before[dimension] }
      worsened.min_by { |dimension| weights[dimension].to_f }
    end
  end

  # Prose over already-computed numbers: the model writes the sentence and never supplies a figure, and a
  # templated fallback says the same when it is unavailable.
  module Explanation
    SCHEMA = { "type" => "object", "additionalProperties" => false,
               "properties" => { "sentence" => { "type" => "string" } }, "required" => ["sentence"] }.freeze

    module_function

    def for(parent, child, requested)
      facts = {
        "price_change_minor" => child.dig("price", "total", "amount_minor") - parent.dig("price", "total", "amount_minor"),
        "currency" => child.dig("price", "total", "currency"),
        "match_before" => parent.dig("match", "score"), "match_after" => child.dig("match", "score"),
        "changes" => Delta.changed_steps(parent, child).map(&:to_s),
        "asked_for" => requested.map { |a| a["dimension"] }
      }

      outcome = AI::Task.run(task: "explain_delta", input: facts, schema: SCHEMA,
                             fallback: ->(input) { { "sentence" => templated(input) } })
      outcome.value["sentence"]
    end

    def templated(facts)
      change = facts["price_change_minor"].to_i
      direction = change.negative? ? "дешевле на #{-change / 100}" : "дороже на #{change / 100}"
      match = "совпадение #{facts["match_before"]} → #{facts["match_after"]}"
      "#{direction} #{facts["currency"]}, #{match}. Изменено: #{Array(facts["changes"]).join(", ")}."
    end
  end
end
