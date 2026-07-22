module Planning
  # Reading a Dream without a model: `AI::Task`'s fallback, a lexicon over the user's own words rather than a
  # guess at meaning. Everything it finds is quoted from the Dream, so the element is genuinely `stated`;
  # everything it cannot map goes to `unmatched_intent` and is shown. The cost of losing the model is recall,
  # and recall failures are displayed rather than hidden.
  module Lexicon
    # Ruby's `\w` is ASCII-only and does not match Cyrillic, so `жив\w*` matches nothing while looking correct.
    # Every stem uses an explicit `[а-яё]*`; `\b` does work against Cyrillic and is kept.
    #
    # dimension => [target, [patterns...]]. Order matters only for readability; matching is exhaustive.
    PATTERNS = [
      ["sea_access", "high", [/\bмор[ею]\b/i, /\bморск/i, /\bпляж/i]],
      ["quiet", "high", [/\bтих/i, /\bтишин/i, /\bспокойн/i]],
      ["food_quality", "high", [/\bвкусн/i, /\bресторан/i, /\bпоесть\b/i, /\bгастро/i, /\bкухн/i]],
      ["walkability", "high", [/\bпешком\b/i, /\bгулять\b/i, /\bпрогулк/i, /\bобходить\b/i, /\bпешеход/i]],
      ["comfort", "high", [/\bкомфорт/i, /хорош[а-яё]*\s+отел/i, /\bуютн/i]],
      ["transfer_simplicity", "high", [/\bтрансфер/i, /\bдобира/i, /после\s+перелёта/i, /после\s+перелета/i]],
      ["nightlife", 0.8, [/вечерн[а-яё]*\s+жизн/i, /\bночн[а-яё]*\s+жизн/i, /\bбар[ыов]?\b/i, /\bклуб/i, /\bтусов/i]],
      ["nature_vs_city", 0.15, [/\bгор[аыу]\b/i, /\bгорн/i, /\bприрод/i, /\bлес\b/i]],
      ["nature_vs_city", 0.85, [/жив[а-яё]*\s+город/i, /\bгородск[а-яё]*\s+жизн/i]],
      ["nature_vs_city", 0.5, [/немного\s+город/i]],
      ["crowds", 0.15, [/минимум\s+людей/i, /\bтолп/i, /туристическ[а-яё]*\s+мест/i, /\bбез\s+людей/i, /\bне\s+людн/i]],
      ["climate_warm", 25.0, [/\bтепл/i, /\bжарк/i, /\bгреться\b/i]],
      ["car_free", true, [/без\s+машин/i, /без\s+авто/i, /\bне\s+хотим\s+водить/i]]
    ].freeze

    MONTHS = { "январ" => 1, "феврал" => 2, "март" => 3, "апрел" => 4, "ма[йея]" => 5, "июн" => 6, "июл" => 7,
               "август" => 8, "сентябр" => 9, "октябр" => 10, "ноябр" => 11, "декабр" => 12 }.freeze

    Match = Struct.new(:dimension, :target, :quote, keyword_init: true)

    module_function

    # Everything the lexicon can see, each with the words that produced it.
    def matches(dream)
      text = dream.to_s
      found = PATTERNS.filter_map do |dimension, target, patterns|
        quote = patterns.filter_map { |pattern| text[pattern] }.first
        next unless quote

        Match.new(dimension: dimension, target: target, quote: quote)
      end

      # One dimension, one element: the most specific reading wins, by the order the table is written in.
      found.uniq(&:dimension) + [budget(text), trip_length(text), dates(text)].compact
    end

    NAMED_BUDGET = /(?:умеренн[а-яё]*|скромн[а-яё]*|небольш[а-яё]*|ограничен[а-яё]*)\s+бюджет|бюджет\b|\bнедорого\b|подешевле/i

    def budget(text)
      amount = /(?:до|не\s+дороже|бюджет[а-яё]*\s+до|в\s+пределах)\s*([\d][\d  ]*)\s*(?:₽|руб|р\.|тыс)/i
      if (raw = text[amount, 1])
        return Match.new(dimension: "total_budget", target: raw.gsub(/[\s ]/, "").to_i * 100,
                         quote: text[/(?:до|не\s+дороже|бюджет[а-яё]*\s+до|в\s+пределах)\s*[\d][\d  ]*\s*(?:₽|руб|р\.|тыс)/i])
      end

      # "Умеренный бюджет" names the dimension without the number: a stated preference with an unknown bound,
      # kept, with the clarification asking for the figure.
      quote = text[NAMED_BUDGET]
      quote && Match.new(dimension: "total_budget", target: nil, quote: quote)
    end

    def trip_length(text)
      if (quote = text[/на\s+недел[юия]/i])
        return Match.new(dimension: "trip_length", target: { "min_nights" => 6, "max_nights" => 8 }, quote: quote)
      end

      nights = text[/на\s+(\d+)\s*(?:ноч|дн|день|дней)/i, 1]
      return nil unless nights

      Match.new(dimension: "trip_length", target: { "min_nights" => nights.to_i - 1, "max_nights" => nights.to_i + 1 },
                quote: text[/на\s+\d+\s*(?:ноч[а-яё]*|дн[а-яё]*|день|дней)/i])
    end

    def dates(text)
      MONTHS.each do |stem, number|
        quote = text[/в?\s*#{stem}[а-яё]*/i]
        next unless quote && text.match?(/#{stem}/i)

        return Match.new(dimension: "dates", target: { "month" => number }, quote: quote.strip)
      end
      nil
    end

    # Party is a fact about the trip, not a Travel DNA dimension; the contract spec asserts it.
    def party(text)
      return { "adults" => 2, "children" => 0 } if text.match?(/вдво[её]м|на\s+двоих|вдвоем/i)
      return { "adults" => 1, "children" => 0 } if text.match?(/один|одна|соло/i)

      nil
    end

    # What the lexicon could not place, shown to the user: dropping intent silently turns this into filters.
    def leftovers(dream, matches)
      quoted = matches.map(&:quote).compact
      dream.to_s.split(/[.,;!?\n]+/).map(&:strip).reject do |phrase|
        phrase.length < 4 || quoted.any? { |quote| phrase.downcase.include?(quote.to_s.downcase) }
      end
    end
  end
end
