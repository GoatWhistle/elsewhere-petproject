require "json"
require "date"
require_relative "http"
require_relative "page_cache"

module Supply
  # Open-Meteo: climate normals and the forecast, no API key. The free tier is non-commercial only — fine for
  # this build, a paid dependency the day it is not. Quoted limits are 10 000 calls/day, 5 000/hour,
  # 600/minute; we make seven.
  module OpenMeteo
    ARCHIVE = "https://archive-api.open-meteo.com/v1/archive".freeze
    MARINE = "https://marine-api.open-meteo.com/v1/marine".freeze
    FORECAST = "https://api.open-meteo.com/v1/forecast".freeze

    DAILY = %w[temperature_2m_mean temperature_2m_min temperature_2m_max precipitation_sum].freeze
    FORECAST_DAILY = %w[temperature_2m_mean temperature_2m_min temperature_2m_max
                        precipitation_sum precipitation_probability_mean].freeze

    Answer = Struct.new(:daily, :reason, :from_cache, keyword_init: true) do
      def assessed? = reason.nil?
    end

    module_function

    # Daily history, for aggregating into normals. Cached forever: 1995–2024 does not change.
    def archive(lat:, lon:, from:, to:, cache: PageCache.new, offline: false)
      get(ARCHIVE, { latitude: lat, longitude: lon, start_date: from, end_date: to,
                     daily: DAILY.join(","), timezone: "UTC" }, cache: cache, offline: offline)
    end

    # Sea surface temperature. The marine archive starts in 2023, so this is a three-year mean, recorded as one.
    def marine(lat:, lon:, from:, to:, cache: PageCache.new, offline: false)
      get(MARINE, { latitude: lat, longitude: lon, start_date: from, end_date: to,
                    daily: "sea_surface_temperature_mean", timezone: "UTC" }, cache: cache, offline: offline)
    end

    # A forecast is worth something only while fresh: past the maximum age the cache is a miss, not a stale hit.
    FORECAST_MAX_AGE_S = 3 * 3600

    def forecast(lat:, lon:, from:, to:, cache: PageCache.new, offline: false)
      get(FORECAST, { latitude: lat, longitude: lon, start_date: from, end_date: to,
                      daily: FORECAST_DAILY.join(","), timezone: "auto" },
          cache: cache, offline: offline, max_age: FORECAST_MAX_AGE_S)
    end

    # Metered by data volume, not request count: thirty years of daily history for one city can trip
    # "Minutely API request limit exceeded". The limit is per minute, so the answer is to wait it out.
    RETRY_AFTER_S = 65

    def with_quota(attempts: 3)
      attempts.times do |attempt|
        response = yield
        return response unless response.status == 429
        return response if attempt == attempts - 1

        warn("open-meteo: minutely limit reached, waiting #{RETRY_AFTER_S}s")
        sleep(RETRY_AFTER_S)
      end
    end

    def get(endpoint, params, cache:, offline:, max_age: nil)
      url = "#{endpoint}?#{URI.encode_www_form(params.sort_by { |key, _| key.to_s })}"

      failure = nil
      entry = cache.fetch(url, max_age: max_age) do
        next nil if offline

        response = with_quota { Http.get(url, timeout: 60, min_interval: 1.0) }
        unless response.ok?
          failure = response.error || "HTTP #{response.status}: #{response.json&.dig("reason") || response.body.to_s[0, 120]}"
          next nil
        end

        cache.write(url, status: response.status, body: response.body)
      end
      return Answer.new(reason: failure || (offline ? "not cached, and offline" : "no answer from Open-Meteo")) if entry.nil?

      daily = JSON.parse(entry.body)["daily"]
      daily ? Answer.new(daily: daily, from_cache: entry.from_cache?) : Answer.new(reason: "Open-Meteo returned no daily series")
    rescue JSON::ParserError => e
      Answer.new(reason: "unparseable Open-Meteo answer: #{e.message}")
    end
  end
end
