module Supply
  module Harvest
    # 101hotels.com, the catalogue source chosen by DEC-016. Everything here was read from the site's own
    # robots.txt or seen in a captured response, never inferred from how listing sites usually work.
    module Catalogue101
      HOST = "https://101hotels.com".freeze

      # robots.txt, `User-agent: *`, read 2026-08-27. The catalogue lives under /main/cities/**, which is not
      # in the disallowed set; /search and /city* are, and we never touch them.
      DISALLOWED = %w[/search /city /redirect /favorites /nearby/location /booking/order_form /app /mobile_app].freeze
      CATALOGUE_PREFIX = "/main/cities/".freeze

      # robots.txt sets `Crawl-delay: 8` for Bingbot only and nothing for us; four seconds is slower than a
      # person clicking through the site.
      MIN_INTERVAL_S = 4.0

      module_function

      def city_url(slug) = "#{HOST}#{CATALOGUE_PREFIX}#{slug}"
      def category_url(slug, category) = "#{HOST}#{CATALOGUE_PREFIX}#{slug}/#{category}"
      def property_url(path) = "#{HOST}#{path}"

      def allowed?(path)
        path.to_s.start_with?(CATALOGUE_PREFIX) && DISALLOWED.none? { |prefix| path.to_s.start_with?(prefix) }
      end

      # The city page links its own sub-listings, each re-slicing the city into a different 21. Read off the
      # page rather than hardcoded: the set differs per city and only three were verified by hand.
      def categories_on(html, slug)
        html.to_s.scan(/href="(#{Regexp.escape(CATALOGUE_PREFIX)}#{Regexp.escape(slug)}\/[a-z0-9_]+)"/)
            .flatten.uniq
            .reject { |path| path.end_with?(".html") }
            .map { |path| path.split("/").last }
      end
    end
  end
end
