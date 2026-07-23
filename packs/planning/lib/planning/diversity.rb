require_relative "match"

module Planning
  # Stage 5: which three, and why (DEC-022). A is the best match, B is cheaper within 0.08 of A, C is a
  # different geography within 0.12 of A. Named archetypes rather than a spread metric: an archetype explains
  # itself in the sentence the contract already requires, and the thresholds answer how much match is traded
  # for difference. Never padded — if C cannot clear its floor, two Futures come back with a note saying so.
  module Diversity
    CHEAPER_FLOOR = 0.08
    DIFFERENT_FLOOR = 0.12

    # The corpus priority: cities carry the demo, mountains and sea supply the contrast.
    GEOGRAPHY_ORDER = %w[city mountains sea].freeze

    Selection = Struct.new(:chosen, :note, keyword_init: true)

    module_function

    def select(priced)
      return Selection.new(chosen: [], note: nil) if priced.empty?

      best = priced.min_by { |assembled| Match.ranking_key(assembled["candidate"].match) }
      cheaper = pick_cheaper(priced, best)
      different = pick_different(priced, best, cheaper)

      chosen = [[best, reason_for(:best, best)]]
      chosen << [cheaper, reason_for(:cheaper, cheaper, best)] if cheaper
      chosen << [different, reason_for(:different, different)] if different

      Selection.new(chosen: chosen, note: note_for(chosen, cheaper, different, priced, best))
    end

    def score_of(assembled) = assembled["candidate"].match["score"].to_f
    def total_of(assembled) = assembled.dig("price", "total", "amount_minor").to_i
    def geography_of(assembled) = assembled["candidate"].geography

    # The cheapest option that has not fallen too far behind on match. Cheaper than A, or it is not archetype B.
    def pick_cheaper(priced, best)
      floor = score_of(best) - CHEAPER_FLOOR

      (priced - [best]).select { |assembled| score_of(assembled) >= floor && total_of(assembled) < total_of(best) }
                       .min_by { |assembled| total_of(assembled) }
    end

    # A genuinely different place, in the corpus's own priority order, still above its floor.
    def pick_different(priced, best, cheaper)
      floor = score_of(best) - DIFFERENT_FLOOR
      taken = [best, cheaper].compact
      taken_geographies = taken.map { |assembled| geography_of(assembled) }.compact

      candidates = (priced - taken).select do |assembled|
        score_of(assembled) >= floor && !taken_geographies.include?(geography_of(assembled))
      end

      candidates.min_by do |assembled|
        [GEOGRAPHY_ORDER.index(geography_of(assembled)) || GEOGRAPHY_ORDER.length,
         *Match.ranking_key(assembled["candidate"].match)]
      end
    end

    def reason_for(archetype, assembled, best = nil)
      case archetype
      when :best
        top = Array(assembled["candidate"].match["contributions"]).max_by { |c| c["contribution"] }
        "Лучшее совпадение с тем, что вы описали#{top ? ": #{top["explanation"]}" : ""}"
      when :cheaper
        saved = (total_of(best) - total_of(assembled)) / 100
        "Дешевле на #{saved} #{assembled.dig("price", "total", "currency")} при почти том же совпадении"
      when :different
        "Другая география — #{assembled["candidate"].destination.name}, чтобы было из чего выбирать"
      end
    end

    # Says what the set is and what it is missing: silence would read as "there were only two".
    def note_for(chosen, cheaper, different, priced, best)
      return nil if chosen.length >= 3

      parts = ["Вариантов #{chosen.length}, а не три."]
      parts << "Дешевле того же качества не нашлось." if cheaper.nil?
      if different.nil?
        floor = (score_of(best) - DIFFERENT_FLOOR).round(2)
        taken = [best, cheaper].compact.map { |assembled| geography_of(assembled) }.compact
        # "Nothing else existed" and "what existed was not good enough" are different facts.
        elsewhere = (priced - [best, cheaper].compact).reject { |a| taken.include?(geography_of(a)) }
        parts << if elsewhere.empty?
                   "Другой географии в подборке не осталось."
                 else
                   "Вариант другой географии есть, но не дотягивает до порога #{floor} по совпадению — " \
                     "показывать его как альтернативу было бы нечестно."
                 end
      end
      parts.join(" ")
    end
  end
end
