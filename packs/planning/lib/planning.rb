require "date"
require "time"
require_relative "../../shared/lib/elsewhere/values"
require_relative "elsewhere/store"
require_relative "../../shared/lib/ai/task"
require_relative "../../supply/lib/supply"
require_relative "planning/taxonomy"
require_relative "planning/lexicon"
require_relative "planning/clarifications"
require_relative "planning/dream_parser"
require_relative "planning/dna_store"
require_relative "planning/constraints"
require_relative "planning/curves"
require_relative "planning/match"
require_relative "planning/candidates"
require_relative "planning/assembly"
require_relative "planning/diversity"
require_relative "planning/instructions"
require_relative "planning/delta"
require_relative "planning/simulator_core"

module Planning
  module_function

  def now; Time.now.utc.iso8601; end

  module Sessions
    module_function
    def now; Time.now.utc.iso8601; end
    def create(dream_text:, origin:, date_window:, party:)
      id = Elsewhere::Store.id
      draft = TravelDna.draft(dream_text, date_window, party)
      # The stored version is the record; the draft still carries its unanswered questions.
      dna = DnaStore.create(session_id: id, dna: draft).merge("_clarifications" => draft["_clarifications"])
      # Clarifications belong to the session, not the DNA: questions not yet asked, not beliefs about the user.
      session = { "id" => id, "created_at" => now, "dream_text" => dream_text, "travel_dna" => TravelDna.without_internals(dna),
                  "clarifications" => dna["_clarifications"] || [], "_origin" => origin,
                  "_date_window" => date_window, "_party" => party,
                  # Surfaced rather than acted on: a DNA the model never saw is not the same fact as one it did.
                  "_dna_degraded" => dna["_degraded"], "_dna_degraded_reason" => dna["_degraded_reason"] }
      Elsewhere::Store.save_session(session)
    end
    def find(id:); Elsewhere::Store.find_session(id); end
    def public(session); session.select { |key, _| %w[id created_at dream_text travel_dna clarifications].include?(key) }; end
  end

  module TravelDna
    module_function
    # Party is a fact about the trip and lives on the session, not a Travel DNA dimension.
    def draft(dream, date_window, _party)
      parsed = DreamParser.parse(dream)
      elements = parsed.elements.dup

      # Dates become a hard constraint; the party never becomes a dimension, and the contract spec asserts it.
      elements = elements.reject { |element| element["dimension"] == "dates" } +
                 [DreamParser.element("dates", date_window, "stated", DreamParser::NAMED)] if date_window

      { "id" => Elsewhere::Store.id, "version" => 1, "elements" => elements,
        "unmatched_intent" => parsed.unmatched_intent,
        "_clarifications" => parsed.clarifications, "_degraded" => parsed.degraded,
        "_degraded_reason" => parsed.degraded_reason }
    end

    INTERNAL_KEYS = %w[_clarifications _degraded _degraded_reason].freeze

    # Internal bookkeeping never crosses the serialization boundary; the conformance spec fails when it does.
    # Not named `public`: that is Module#public, and shadowing it makes the method private on the singleton.
    def without_internals(dna)
      dna.reject { |key, _| INTERNAL_KEYS.include?(key) }
         .merge("elements" => Array(dna["elements"]).map { |element| element.reject { |key, _| key.start_with?("_") } })
    end

    # An upsert by dimension that produces a new version. Editing one field must not erase the rest.
    def update(session_id:, elements:)
      dna = DnaStore.update(session_id: session_id, elements: elements)
      session = Sessions.find(id: session_id)
      session["travel_dna"] = without_internals(dna)
      Elsewhere::Store.save_session(session)
      session["travel_dna"]
    end

    # Answering removes that question only; wiping the list would lose the ones not yet asked.
    def answer_clarifications(session_id:, answers:)
      session = Sessions.find(id: session_id)
      answered = Array(answers).map { |answer| (answer["id"] || answer[:id]).to_s }
      elements = Array(answers).filter_map { |answer| clarification_element(answer) }

      dna = elements.any? ? DnaStore.update(session_id: session_id, elements: elements) : DnaStore.find(session_id)
      session["clarifications"] = Array(session["clarifications"]).reject { |c| answered.include?(c["id"]) }
      session["travel_dna"] = without_internals(dna)
      Elsewhere::Store.save_session(session)
      session["travel_dna"]
    end

    # Only dimension answers change the DNA. Party and dates live on the session, and `budget_hard` says
    # whether an existing element is a ceiling, not what it is.
    def clarification_element(answer)
      id = (answer["id"] || answer[:id]).to_s
      value = answer.key?("value") ? answer["value"] : answer[:value]
      return nil unless id == "car_free"

      { "dimension" => "car_free", "kind" => "hard_constraint", "target" => value }
    end
  end

  module Futures
    module_function

    def now = Time.now.utc.iso8601

    FARE_BUDGET = 24   # per generation (DEC-028); asserted in the specs, not merely intended

    def generate(session_id:)
      session = Sessions.find(id: session_id)
      dna = DnaStore.find(session_id) || session["travel_dna"]
      constraints = Constraints.from(dna, date_window: session["_date_window"], party: session["_party"])
      months = months_in(constraints)
      budget = Assembly::Budget.new(fare_requests: [])

      shortlist = Candidates.shortlist(dna, constraints, months: months)
      priced, refused = assemble_all(shortlist, constraints, session, budget).partition { |a| a["refused"].nil? }

      return no_solution(constraints) if priced.empty?

      selection = Diversity.select(priced)
      futures = selection.chosen.map { |assembled, reason| build(session, dna, assembled, reason) }
      futures.each { |future| Elsewhere::Store.save_future(future) }
      note = diversity_note(futures, refused, selection.note)
      session["_diversity_note"] = note
      Elsewhere::Store.save_session(session)

      { "kind" => "futures", "futures" => futures.map { |future| public(future) } }
    end

    def assemble_all(shortlist, constraints, session, budget)
      fares = {}
      shortlist.filter_map do |candidate|
        assembled = Assembly.assemble(candidate, constraints, origin: session.fetch("_origin"),
                                                              party: session["_party"], fares: fares, budget: budget)
        next if assembled.nil?
        next assembled if assembled["refused"]
        # The final gate: a violation removes a candidate, it never lowers a score.
        next unless Constraints.violations(assembled, constraints).empty?

        assembled
      end
    end

    # Why the set looks the way it does. Never padded to three, and never silently short either.
    def diversity_note(futures, refused, selection_note)
      reasons = refused.map { |item| item["refused"] }.uniq
      return nil if futures.length >= 3 && reasons.empty?

      parts = [selection_note].compact
      parts << "Отброшено направлений: #{refused.length} — #{reasons.first}" if reasons.any?
      parts.join(" ")
    end

    def months_in(constraints)
      window = constraints.date_window
      return [Date.today.month] unless window

      (window[:from]..window[:to]).map(&:month).uniq
    end

    def no_solution(constraints)
      rejections = Constraints.destinations(Supply::Catalog.destinations, constraints).rejections
      { "kind" => "no_solution", "no_solution" => Constraints.no_candidates(rejections, constraints) }
    end

    # FutureSet: the Futures plus why the set is the shape it is (see provider_adapters.md).
    def list(session_id:)
      { "futures" => Elsewhere::Store.futures_for_session(session_id),
        "diversity_note" => Sessions.find(id: session_id)&.dig("_diversity_note") }
    end
    def find(future_id:) = Elsewhere::Store.find_future(future_id)

    # `session_id` indexes a Future in the store and is not in the contract, so it is stripped at the
    # serialization boundary; the conformance spec fails when it leaks.
    INTERNAL_KEYS = %w[session_id _drag].freeze
    def public(future); future && future.reject { |key, _| INTERNAL_KEYS.include?(key) }; end

    def build(session, dna, assembled, reason, parent: nil, version: 1)
      candidate = assembled["candidate"]
      id = Elsewhere::Store.id
      {
        "id" => id, "session_id" => session["id"],
        "lineage_id" => parent ? parent["lineage_id"] : id, "version" => version,
        "travel_dna_version_id" => dna["id"], "parent_id" => parent && parent["id"],
        "created_at" => now, "expires_at" => (Time.now + 3600).utc.iso8601,
        "destination" => destination_of(candidate),
        "check_in" => assembled["check_in"], "check_out" => assembled["check_out"],
        "accommodation" => accommodation(candidate, assembled["rate"]),
        "logistics" => assembled["logistics"], "price" => assembled["price"],
        "match" => candidate.match, "why_this_exists" => reason,
        "benefits" => benefits(candidate), "compromises" => compromises(candidate),
        "delta" => nil, "forecast_summary" => []
      }
    end

    def destination_of(candidate)
      d = candidate.destination
      { "city_code" => d.city_code, "name" => d.name, "country" => d.country, "coordinates" => d.coordinates }
    end

    def accommodation(candidate, rate)
      geo = Supply::Geo.features(property_id: candidate.property.catalogue_id) || {}
      {
        "catalogue_id" => candidate.property.catalogue_id, "name" => candidate.property.name,
        "room_name" => "Стандартный номер", "handoff_url" => rate["handoff_url"],
        "coordinates" => candidate.property.coordinates,
        "cancellation" => { "refundable" => true, "free_until" => nil,
                            "summary" => "Условия отмены не публикуются источником" },
        "distance_to_sea_m" => geo["distance_to_sea_m"], "distance_to_centre_m" => geo["distance_to_centre_m"]
      }
    end

    # Straight off the decomposition: what this candidate is good at, and where it pays for it.
    def benefits(candidate)
      candidate.match["contributions"].select { |c| c["satisfaction"] >= 0.75 }
               .sort_by { |c| -c["contribution"] }.first(3).map { |c| c["explanation"] }
    end

    def compromises(candidate)
      weak = candidate.match["contributions"].select { |c| c["satisfaction"] < 0.5 }
                      .sort_by { |c| c["satisfaction"] }.first(2).map { |c| c["explanation"] }
      gaps = candidate.match["unscored_dimensions"].map { |u| u["reason"] }
      (weak + gaps).first(3)
    end
  end

  module Simulator
    module_function

    # The single entry point for any modification of a Future — sliders, natural language and applied
    # mitigations all route through here.
    def simulate(future_id:, adjustments: nil, instruction: nil, persist_to_dna: false)
      SimulatorCore.simulate(future_id: future_id, adjustments: adjustments, instruction: instruction,
                             persist_to_dna: persist_to_dna)
    end
  end
end
