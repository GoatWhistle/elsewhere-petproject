require "json"
require_relative "harvest"

module Supply
  # Which destinations the corpus contains, and the evidence that it is not homogeneous (OQ-B). Diversity is
  # impossible over a homogeneous set, so the corpus is curated on three axes and the spread is asserted.
  # Price and popularity are measured from the harvest; geography is a declared judgement — nothing in the
  # harvest says "this is a mountain town".
  module Corpus
    GEOGRAPHY_TYPES = %w[city mountains sea].freeze

    # `peak_season` is the second declared judgement: nothing in the climate says a ski resort is busiest at
    # −16 °C, and reading "warm means expensive" off the thermometer puts Sheregesh's high season in July.
    PEAK_SEASONS = %w[warm cold].freeze

    Entry = Struct.new(:slug, :city_code, :name, :country, :geography_type, :peak_season, :note,
                       keyword_init: true) do
      def to_city
        { slug: slug, city_code: city_code, name: name, country: country,
          geography_type: geography_type, peak_season: peak_season }
      end
    end

    # Every slug returned HTTP 200 with a full listing during the first probe; nothing here is assumed to
    # exist. Each city_code is a real IATA code for a city with its own airport. Geography priority is
    # city > mountains > sea: cities harvest most reliably, the rest supply the contrast.
    MANIFEST = [
      Entry.new(slug: "sankt-peterburg", city_code: "LED", name: "Санкт-Петербург", country: "Россия",
                geography_type: "city", peak_season: "warm", note: "Крупнейший городской корпус: плотная застройка, максимум POI"),
      Entry.new(slug: "kazan", city_code: "KZN", name: "Казань", country: "Россия",
                geography_type: "city", peak_season: "warm", note: "Компактный центр — контраст к Петербургу по масштабу"),
      Entry.new(slug: "kaliningrad", city_code: "KGD", name: "Калининград", country: "Россия",
                geography_type: "city", peak_season: "warm", note: "Город у холодного моря — не «тёплое море», а именно город"),
      Entry.new(slug: "kislovodsk", city_code: "MRV", name: "Кавказские Минеральные Воды", country: "Россия",
                geography_type: "mountains", peak_season: "warm", note: "Горы и курортный парк, сезон летний, ближайший аэропорт MRV"),
      Entry.new(slug: "sheregesh", city_code: "NOZ", name: "Шерегеш", country: "Россия",
                geography_type: "mountains", peak_season: "cold", note: "Горнолыжный: пик зимой, а не летом: далеко, дёшево, сезонно"),
      Entry.new(slug: "sochi", city_code: "AER", name: "Сочи", country: "Россия",
                geography_type: "sea", peak_season: "warm", note: "Тёплое море, самый дорогой и самый людный конец обеих осей"),
      Entry.new(slug: "anapa", city_code: "AAQ", name: "Анапа", country: "Россия",
                geography_type: "sea", peak_season: "warm", note: "Тёплое море дешевле Сочи — иначе ось «дорого/дёшево» схлопывается")
    ].freeze

    # Both ends of the price axis in every city, verified on all seven listing pages, so medians are comparable.
    CATEGORIES = %w[inexpensive expensive].freeze

    Profile = Struct.new(:city_code, :name, :geography_type, :properties, :price_levels_minor,
                         :price_currency, :reviews_total, :reviews_per_property, keyword_init: true) do
      def price_median_minor = Corpus.quantile(price_levels_minor, 0.5)

      def to_h = super.transform_keys(&:to_s)
    end

    module_function

    def manifest = MANIFEST

    # Seeds from disk. `offline: true` by default: `db:seed` must never quietly start a web harvest.
    def seed!(offline: true, categories: CATEGORIES, log: nil)
      Harvest.run(cities: MANIFEST.map(&:to_city), categories: categories, offline: offline, log: log)
    end

    def profiles
      DestinationRecord.order(:city_code).map do |destination|
        properties = PropertyRecord.where(destination_id: destination.id)
        reviews = properties.pluck(:review_count).compact

        Profile.new(
          city_code: destination.city_code, name: destination.name,
          geography_type: destination.geography_type, properties: properties.count,
          price_levels_minor: properties.where.not(price_level_minor: nil).pluck(:price_level_minor).sort,
          price_currency: properties.pick(:price_currency) || "RUB",
          reviews_total: reviews.sum,
          reviews_per_property: (reviews.empty? ? nil : (reviews.sum.to_f / reviews.length).round)
        )
      end
    end

    # Where each axis reaches, and what is missing. Price is read at property level, not by comparing
    # destination medians: both ends are harvested everywhere, so medians converge and a median comparison
    # would call that "no spread". These positions describe this set only — never score a Future with them.
    def coverage(found = profiles)
      geography = GEOGRAPHY_TYPES.to_h { |type| [type, found.count { |profile| profile.geography_type == type }] }

      {
        "destinations" => found.length,
        "properties" => found.sum(&:properties),
        "geography" => geography,
        "price" => price_coverage(found),
        "popularity" => popularity_coverage(found),
        "gaps" => gaps(found, geography)
      }
    end

    def price_coverage(found)
      all = found.flat_map(&:price_levels_minor).sort
      return { "assessed" => false, "reason" => "no property in the corpus has an observed price level" } if all.length < 2

      median = quantile(all, 0.5)
      p10 = quantile(all, 0.10)
      {
        "assessed" => true, "currency" => (found.first&.price_currency || "RUB"), "observed" => all.length,
        "min" => all.first, "p10" => p10, "median" => median, "p90" => quantile(all, 0.90), "max" => all.last,
        "p90_over_p10" => (quantile(all, 0.90).to_f / p10).round(2),
        # The axis is only real if a traveller can choose either end *wherever they go*.
        "destinations_offering_both_ends" => found.count { |profile| both_ends?(profile, median) },
        "destination_medians" => found.to_h { |profile| [profile.city_code, profile.price_median_minor] }
      }
    end

    def both_ends?(profile, corpus_median)
      profile.price_levels_minor.any? { |value| value < corpus_median } &&
        profile.price_levels_minor.any? { |value| value > corpus_median }
    end

    def popularity_coverage(found)
      values = found.filter_map(&:reviews_per_property)
      return { "assessed" => false, "reason" => "no destination has any review count" } if values.length < 2

      low, high = values.minmax
      {
        "assessed" => true, "min" => low, "max" => high, "ratio" => (high.to_f / low).round(2),
        "quietest" => found.min_by { |p| p.reviews_per_property || Float::INFINITY }.city_code,
        "busiest" => found.max_by { |p| p.reviews_per_property || -Float::INFINITY }.city_code,
        "basis" => "catalogue review volume per property — a popularity proxy, not a crowd measurement"
      }
    end

    def gaps(found, geography)
      gaps = GEOGRAPHY_TYPES.reject { |type| geography[type].to_i.positive? }
                            .map { |type| "no #{type} destination in the corpus" }
      gaps << "no destination has any property" if found.empty? || found.all? { |profile| profile.properties.zero? }
      gaps
    end

    def quantile(sorted, fraction)
      return nil if sorted.nil? || sorted.empty?

      sorted[[(sorted.length * fraction).to_i, sorted.length - 1].min]
    end

    # The corpus as it came out, so a spec can assert the real spread without a harvested database.
    # Regenerate with:
    #   bin/rails runner 'File.write("packs/supply/fixtures/corpus_profile.json", Supply::Corpus.snapshot)'
    def snapshot = JSON.pretty_generate(profiles.map(&:to_h))

    def from_snapshot(json)
      JSON.parse(json).map { |row| Profile.new(**row.transform_keys(&:to_sym)) }
    end
  end
end
