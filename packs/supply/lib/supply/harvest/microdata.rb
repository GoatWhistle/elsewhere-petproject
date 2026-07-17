require "cgi"
require "bigdecimal"

module Supply
  module Harvest
    # schema.org microdata, read with regular expressions because the Gemfile has no HTML parser. The markup
    # is machine-oriented `itemprop` output, so it is regular in practice, and every field is asserted against
    # a captured page in the spec. If this starts guessing, add the parser rather than another regex.
    module Microdata
      LODGING_TYPES = %w[Hotel Hostel Motel Resort BedAndBreakfast LodgingBusiness Apartment].freeze
      LODGING_MARKER = /itemtype="https:\/\/schema\.org\/(?:#{LODGING_TYPES.join("|")})"/.freeze

      module_function

      # One hash per lodging on the page, values still as the page wrote them.
      def lodgings(html)
        text = html.to_s
        starts = text.enum_for(:scan, LODGING_MARKER).map { Regexp.last_match.begin(0) }
        return [] if starts.empty?

        (starts + [text.length]).each_cons(2).filter_map do |from, to|
          block = text[from...to]
          record = extract(block)
          record if record[:name] && record[:lat] && record[:lon]
        end
      end

      def extract(block)
        # The lodging's name is element text while amenity blocks use content="…", so only the head of the
        # block reads it unambiguously.
        head = block.split('itemprop="amenityFeature"').first.to_s

        {
          source_id: attribute(block, "data-hotel-id"),
          name: text_prop(head, "name"),
          lat: content_prop(block, "latitude"),
          lon: content_prop(block, "longitude"),
          address: text_prop(block, "streetAddress"),
          rating: text_prop(block, "ratingValue"),
          rating_scale: text_prop(block, "bestRating"),
          review_count: content_prop(block, "reviewCount") || content_prop(block, "ratingCount"),
          price_level_text: content_prop(block, "priceRange"),
          price_value: attribute(block, "data-price-value"),
          price_currency: attribute(block, "data-price-currency") || content_prop(block, "currenciesAccepted"),
          path: block[/href="(\/[^"]+\.html)"/, 1],
          photos: photos(block)
        }
      end

      def content_prop(block, name)
        value = block[/itemprop="#{name}"[^>]*\scontent="([^"]*)"/, 1]
        value && CGI.unescapeHTML(value).strip
      end

      def text_prop(block, name)
        match = block.match(/itemprop="#{name}"[^>]*>(.{0,400}?)<\//m)
        return content_prop(block, name) unless match

        value = strip_tags(match[1])
        value.empty? ? content_prop(block, name) : value
      end

      def attribute(block, name)
        block[/#{name}="([^"]*)"/, 1]
      end

      def photos(block)
        block.scan(/https:\/\/[a-z0-9.\-]*101hotelscdn\.ru\/[^"'\s\\]+\.(?:jpg|jpeg|png|webp)/i).uniq
      end

      def strip_tags(fragment)
        CGI.unescapeHTML(fragment.gsub(/<[^>]*>/, " ")).gsub(/\s+/, " ").strip
      end

      # "от 5 200 руб. средняя цена за номер" / data-price-value="5200" → 520000 minor units.
      # Money is an integer in minor units, never a float, so the decimal goes through BigDecimal.
      def price_minor(record)
        major = record[:price_value] || record[:price_level_text].to_s[/([\d][\d  ]*(?:[.,]\d+)?)/, 1]
        return nil if major.nil? || major.to_s.strip.empty?

        normalised = major.to_s.gsub(/[\s ]/, "").tr(",", ".")
        return nil unless normalised.match?(/\A\d+(?:\.\d+)?\z/)

        (BigDecimal(normalised) * 100).round.to_i
      end

      # "9.4 / 10" → [9.4, 10]: the scale travels with the number.
      def rating(record)
        value = record[:rating].to_s[/(\d+(?:[.,]\d+)?)/, 1]
        return [nil, nil] unless value

        scale = (record[:rating_scale].to_s[/(\d+)/, 1] || record[:rating].to_s[/\/\s*(\d+)/, 1])
        [BigDecimal(value.tr(",", ".")).to_f, scale&.to_i]
      end
    end
  end
end
