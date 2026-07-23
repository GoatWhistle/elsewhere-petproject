require "date"
require_relative "taxonomy"

module Planning
  # Hard constraints: deterministic and disqualifying. A violation removes a candidate and never lowers a
  # score — blurring that is how "up to 180 000 ₽" becomes "we found one at 240 000 but it scored well".
  # Only five may be hard: total budget, dates, trip length, party and `car_free`. Let "quiet" be hard and the
  # result set is empty with nobody able to say why.
  module Constraints
    ENFORCEABLE = %w[total_budget dates trip_length car_free].freeze

    Set = Struct.new(:budget_minor, :currency, :date_window, :min_nights, :max_nights, :party, :car_free,
                     :unenforced, keyword_init: true) do
      def budget? = !budget_minor.nil?
      def car_free? = car_free == true
    end

    Rejection = Struct.new(:city_code, :constraint, :detail, :needed_minor, keyword_init: true)
    Result = Struct.new(:survivors, :rejections, keyword_init: true) do
      def empty? = survivors.empty?
    end

    module_function

    def from(dna, date_window: nil, party: nil)
      elements = Array(dna && dna["elements"]).to_h { |element| [element["dimension"], element] }
      unenforced = []

      budget = enforceable(elements["total_budget"], unenforced)
      dates = enforceable(elements["dates"], unenforced) || (date_window && { "value" => date_window })
      length = enforceable(elements["trip_length"], unenforced)
      car_free = enforceable(elements["car_free"], unenforced)

      Set.new(
        budget_minor: budget.is_a?(Numeric) ? budget : nil, currency: "RUB",
        date_window: window(dates.is_a?(Hash) ? (dates["value"] || dates) : date_window),
        min_nights: length.is_a?(Hash) ? length["min_nights"] : nil,
        max_nights: length.is_a?(Hash) ? length["max_nights"] : nil,
        party: party, car_free: car_free == true, unenforced: unenforced
      )
    end

    # An inferred hard constraint waits for confirmation: otherwise it cuts destinations on something unsaid.
    def enforceable(element, unenforced)
      return nil unless element

      if element["provenance"] == "inferred" || element["provenance"] == "default"
        unenforced << { "dimension" => element["dimension"], "reason" => "inferred, not confirmed by the user" }
        return nil
      end

      element["target"]
    end

    def window(raw)
      return nil unless raw.is_a?(Hash)

      earliest = raw["earliest"] || raw[:earliest]
      latest = raw["latest"] || raw[:latest]
      return nil unless earliest && latest

      { from: Date.parse(earliest.to_s), to: Date.parse(latest.to_s) }
    end

    # ---- stage 1 of the pipeline: destinations, before anything is scored ---------------------------------
    #
    # Local and free. A destination is cut only when it cannot work, never when it looks unpromising.
    def destinations(list, set, nights: nil)
      rejections = []
      survivors = list.select do |destination|
        rejection = reject_destination(destination, set, nights)
        rejections << rejection if rejection
        rejection.nil?
      end

      Result.new(survivors: survivors, rejections: rejections)
    end

    def reject_destination(destination, set, nights)
      code = destination.city_code

      if set.budget?
        floor = cheapest_stay_minor(code, set, nights)
        if floor && floor > set.budget_minor
          return Rejection.new(city_code: code, constraint: "total_budget", needed_minor: floor,
                               detail: "самое дешёвое размещение здесь — #{floor / 100} ₽, " \
                                       "уже больше бюджета #{set.budget_minor / 100} ₽, и это ещё без перелёта")
        end
      end

      if set.car_free? && !car_free_feasible?(code)
        return Rejection.new(city_code: code, constraint: "car_free",
                             detail: "без машины здесь не обойтись: ни один объект не набирает минимальной пешей доступности")
      end

      nil
    end

    # The cheapest stay buildable here: a lower bound, since a fare is still to come.
    def cheapest_stay_minor(city_code, set, nights)
      nights ||= set.min_nights || 7
      window = set.date_window
      check_in = window ? window[:from] : Date.new(2026, 7, 8)

      rates = Supply::Catalog.properties(city_code: city_code, limit: 20).filter_map do |property|
        rate = Supply::Rates.for(property_id: property.catalogue_id, check_in: check_in.to_s,
                                 check_out: (check_in + nights).to_s, adults: adults(set))
        rate.dig("amount", "amount_minor")
      end
      rates.min
    end

    # A different question from Foresight's walkability threshold: not "is this a nice walk" but "can a person
    # live here for a week without a car".
    CAR_FREE_DENSITY = 0.3

    def car_free_feasible?(city_code)
      Supply::Catalog.properties(city_code: city_code, limit: 20).any? do |property|
        features = Supply::Geo.features(property_id: property.catalogue_id) || {}
        features["poi_density"].to_f >= CAR_FREE_DENSITY
      end
    end

    def adults(set) = (set.party && (set.party["adults"] || set.party[:adults])) || 2

    # ---- the final gate: a priced candidate ---------------------------------------------------------------

    def violations(candidate, set)
      problems = []
      total = candidate.dig("price", "total", "amount_minor")
      problems << "total_budget" if set.budget? && total && total > set.budget_minor

      if set.date_window
        check_in = Date.parse(candidate["check_in"].to_s)
        check_out = Date.parse(candidate["check_out"].to_s)
        problems << "dates" if check_in < set.date_window[:from] || check_out > set.date_window[:to]

        nights = (check_out - check_in).to_i
        problems << "trip_length" if set.min_nights && nights < set.min_nights
        problems << "trip_length" if set.max_nights && nights > set.max_nights
      end

      problems.uniq
    end

    def satisfied_by?(candidate, set) = violations(candidate, set).empty?

    # ---- when nothing survives ----------------------------------------------------------------------------
    #
    # Never relax silently: name the constraint doing the cutting and what loosening it would return.
    def no_candidates(rejections, set)
      binding = rejections.group_by(&:constraint).max_by { |_constraint, list| list.length }
      constraint, cut = binding || ["total_budget", []]
      needed = cut.filter_map(&:needed_minor).min

      {
        "reason" => explain(constraint, cut, needed, set),
        "unsatisfiable_constraints" => [constraint],
        "nearest_alternatives" => []
      }
    end

    def explain(constraint, cut, needed, set)
      case constraint
      when "total_budget"
        base = "Ни одно направление не укладывается в бюджет #{set.budget_minor.to_i / 100} ₽ — он отсекает #{cut.length} из них."
        needed ? base + " Самое дешёвое возможное размещение стоит #{needed / 100} ₽, без перелёта." : base
      when "car_free"
        "Без машины ни одно из направлений не работает: #{cut.map(&:city_code).join(", ")} требуют транспорта."
      else
        "Ограничение #{constraint} отсекает все направления."
      end
    end
  end
end
