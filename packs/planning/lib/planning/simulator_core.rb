require "digest"
require_relative "instructions"
require_relative "candidates"
require_relative "assembly"

module Planning
  # The only mutation path for a Future (DEC-025). Sliders, natural language and applied mitigations all
  # arrive here, so nothing else grows its own copy of the pricing and scoring logic.
  module SimulatorCore
    # No dimension in the top three by weight may lose more than this in one operation.
    EPSILON = 0.05
    PROTECTED_COUNT = 3

    # A drag that lands within this window and moves the same dimensions is the same drag.
    COALESCE_SECONDS = 90

    module_function

    def simulate(future_id:, adjustments: nil, instruction: nil, persist_to_dna: false, response: nil)
      original = Futures.find(future_id: future_id)
      raise ArgumentError, "Future not found" unless original

      session = Sessions.find(id: original["session_id"])
      dna = DnaStore.find(original["session_id"]) || session["travel_dna"]

      requested, protect, outcome = resolve(adjustments, instruction, response)
      return unchanged(original, outcome) if requested.empty?

      # "Cheaper" moves the target total, and without a stated budget the only real total is this trip's own
      # price. Seeding from there keeps the step anchored to a number that exists.
      seeded = seed_budget(dna, original, requested)
      adjusted = seeded.merge("elements" => Adjustments.apply(seeded["elements"], requested))
      constraints = Constraints.from(adjusted, date_window: session["_date_window"], party: session["_party"])
      months = Futures.months_in(constraints)

      resolved, blocked = re_solve(session, adjusted, constraints, months)
      return no_solution(original, requested, constraints, blocked) if resolved.nil?
      # A version identical to its parent is not a simulation, it is a no-op wearing a version number.
      return nothing_to_change(original, requested) if same_trip?(original, resolved)

      # ε is a refusal, not a fudge: a move that damages something the user leans on is priced, not made quietly.
      damage = epsilon_breach(original, resolved, dna)
      return refusal(original, resolved, damage, requested) if protect && damage

      persist(session, adjusted) if persist_to_dna
      version = build_version(session, adjusted, original, resolved, requested)
      { "kind" => "future", "future" => Futures.public(version) }
    end

    def seed_budget(dna, original, requested)
      return dna unless requested.any? { |adjustment| adjustment["dimension"] == "total_budget" }
      return dna if Array(dna["elements"]).any? { |element| element["dimension"] == "total_budget" }

      total = original.dig("price", "total", "amount_minor")
      dna.merge("elements" => dna["elements"] + [
                  { "dimension" => "total_budget", "kind" => "hard_constraint", "target" => total,
                    "weight" => nil, "tolerance" => nil, "provenance" => "confirmed", "confidence" => 1.0 }
                ])
    end

    def same_trip?(original, resolved)
      original.dig("accommodation", "catalogue_id") == resolved["candidate"].property.catalogue_id &&
        original["check_in"] == resolved["check_in"] && original["check_out"] == resolved["check_out"]
    end

    # Not a failure of the request, a fact about the corpus: from here, there is nothing to move to.
    def nothing_to_change(_original, requested)
      moves = requested.map { |adjustment| adjustment["dimension"] }.join(", ")
      {
        "kind" => "no_solution",
        "no_solution" => {
          "reason" => "Из этой точки по «#{moves}» двигаться некуда: среди доступных вариантов нет ни одного, " \
                      "который был бы лучше по этому запросу и не нарушал ваши условия.",
          "unsatisfiable_constraints" => requested.map { |adjustment| adjustment["dimension"] }.uniq,
          "nearest_alternatives" => []
        }
      }
    end

    def resolve(adjustments, instruction, response)
      listed = Array(adjustments).filter_map { |raw| Instructions.normalise(raw) }
      return [listed, false, nil] if listed.any?
      return [[], false, nil] if instruction.to_s.strip.empty?

      parsed, protect, outcome = Instructions.parse(instruction, response: response)
      [parsed, protect, outcome]
    end

    # Weight and target changes re-solve over existing candidates; only dates and destinations return to Supply
    # (DEC-025). Returns [best, blocked], where `blocked` records what the final gate turned away, so a refusal
    # can name the step that did the cutting.
    def re_solve(session, adjusted, constraints, months)
      shortlist = Candidates.shortlist(adjusted, constraints, months: months)
      return [nil, []] if shortlist.empty?

      fares = {}
      blocked = []
      priced = shortlist.filter_map do |candidate|
        assembled = Assembly.assemble(candidate, constraints, origin: session.fetch("_origin"),
                                                              party: session["_party"], fares: fares)
        next if assembled.nil? || assembled["refused"]

        violations = Constraints.violations(assembled, constraints)
        if violations.any?
          blocked << [assembled, violations]
          next
        end
        assembled
      end
      return [nil, blocked] if priced.empty?

      [priced.min_by { |assembled| Match.ranking_key(assembled["candidate"].match) }, blocked]
    end

    # The three dimensions this traveller leans on hardest, and whether any of them just lost too much.
    def epsilon_breach(original, resolved, dna)
      protected_dimensions = Array(dna["elements"]).reject { |e| e["weight"].nil? }
                                                   .sort_by { |e| -e["weight"].to_f }
                                                   .first(PROTECTED_COUNT).map { |e| e["dimension"] }
      before = satisfactions(original["match"])
      after = satisfactions(resolved["candidate"].match)

      protected_dimensions.filter_map do |dimension|
        loss = before[dimension].to_f - after[dimension].to_f
        next if loss <= EPSILON

        { "dimension" => dimension, "loss" => loss.round(4) }
      end.max_by { |breach| breach["loss"] }
    end

    def satisfactions(match)
      Array(match && match["contributions"]).to_h { |c| [c["dimension"], c["satisfaction"]] }
    end

    def refusal(original, resolved, damage, _requested)
      saving = original.dig("price", "total", "amount_minor") - resolved.dig("price", "total", "amount_minor")
      {
        "kind" => "no_solution",
        "no_solution" => {
          "reason" => "Дальше дешевеет только за счёт «#{damage["dimension"]}» — потеря #{damage["loss"]} " \
                      "при экономии #{saving / 100} #{original.dig("price", "total", "currency")}. " \
                      "Не делаю это молча: решать вам.",
          "unsatisfiable_constraints" => [damage["dimension"]],
          "nearest_alternatives" => []
        }
      }
    end

    def no_solution(original, requested, constraints, blocked)
      dimensions = requested.map { |adjustment| adjustment["dimension"] }.uniq

      if blocked.any?
        cheapest = blocked.map { |assembled, _| assembled.dig("price", "total", "amount_minor") }.min
        currency = original.dig("price", "total", "currency")
        reason = "Ничего дешевле #{constraints.budget_minor.to_i / 100} #{currency} среди доступных вариантов нет: " \
                 "самый дешёвый из них стоит #{cheapest / 100} #{currency}."
        return { "kind" => "no_solution",
                 "no_solution" => { "reason" => reason,
                                    "unsatisfiable_constraints" => (dimensions + blocked.flat_map(&:last)).uniq,
                                    "nearest_alternatives" => [] } }
      end

      rejections = Constraints.destinations(Supply::Catalog.destinations, constraints).rejections
      answer = Constraints.no_candidates(rejections, constraints)
      answer["unsatisfiable_constraints"] = (dimensions + answer["unsatisfiable_constraints"]).uniq
      { "kind" => "no_solution", "no_solution" => answer }
    end

    def unchanged(original, _outcome)
      { "kind" => "future", "future" => Futures.public(original) }
    end

    def persist(session, adjusted)
      DnaStore.update(session_id: session["id"], elements: adjusted["elements"])
    end

    # ---- versions -----------------------------------------------------------------------------------------

    def signature(requested) = Digest::SHA1.hexdigest(requested.map { |a| a["dimension"] }.sort.join(","))

    # A dragged slider is one version, not one per pixel: the superseded intermediate is removed, never updated.
    def build_version(session, adjusted, original, resolved, requested)
      drag = signature(requested)
      superseded = coalescible(original, drag)
      parent = superseded ? Futures.find(future_id: superseded["parent_id"]) || original : original

      version = Futures.build(session, adjusted, resolved, reason_for(requested), parent: parent,
                                                                                 version: parent["version"] + 1)
      version["_drag"] = drag
      version["delta"] = Delta.between(parent, version, requested)

      Elsewhere::Store.delete_future(superseded["id"]) if superseded
      Elsewhere::Store.save_future(version)
      version
    end

    def coalescible(original, drag)
      return nil unless original["_drag"] == drag && original["parent_id"]
      return nil if Time.now.utc - Time.parse(original["created_at"]) > COALESCE_SECONDS

      original
    end

    def reason_for(requested)
      moves = requested.map { |a| "#{a["dimension"]} #{a["direction"] == "increase" ? "выше" : "ниже"}" }
      "По вашей правке: #{moves.join(", ")}"
    end
  end
end
