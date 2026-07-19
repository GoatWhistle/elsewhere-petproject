require "date"
require_relative "open_meteo"

module Supply
  # Climate normals per destination and month, plus the forecast. Normals are aggregated once from daily
  # history and stored; the forecast is fetched on demand with a short maximum age. Different kinds of fact,
  # labelled `cached` against `live`.
  module ClimateData
    # The most recent thirty years rather than WMO's 1991–2020: a normal ending five years ago understates a
    # warming trend.
    AIR_YEARS = ((Date.today.year - 30)..(Date.today.year - 1)).freeze

    # The marine archive starts in 2023, so the sea figure is a three-year mean and says so.
    SEA_FROM = Date.new(2023, 1, 1)

    # A rain day is ≥ 1 mm; every source picks its own threshold, so the number needs one stated.
    RAIN_DAY_MM = 1.0

    Summary = Struct.new(:destinations, :months, :with_sea, :errors, :notes, keyword_init: true) do
      def to_s
        "#{months} monthly normals for #{destinations} destinations (#{with_sea} with sea temperature) · " \
          "#{errors} errored#{notes.empty? ? "" : " · #{notes.join("; ")}"}"
      end
    end

    module_function

    def refresh!(city_codes: nil, cache: PageCache.new, offline: false, log: nil)
      summary = Summary.new(destinations: 0, months: 0, with_sea: 0, errors: 0, notes: [])

      destinations(city_codes).each do |destination|
        air = OpenMeteo.archive(lat: destination.lat, lon: destination.lon,
                                from: "#{AIR_YEARS.first}-01-01", to: "#{AIR_YEARS.last}-12-31",
                                cache: cache, offline: offline)
        unless air.assessed?
          summary.errors += 1
          log&.call("#{destination.city_code}: air history — #{air.reason}")
          next
        end

        sea = OpenMeteo.marine(lat: destination.lat, lon: destination.lon,
                               from: SEA_FROM.to_s, to: (Date.today - 7).to_s, cache: cache, offline: offline)
        summary.destinations += 1
        store!(destination, air, sea, summary, log)
      end

      summary
    end

    def store!(destination, air, sea, summary, log)
      air_by_month = monthly_air(air.daily)
      sea_by_month = sea.assessed? ? monthly_sea(sea.daily) : {}
      sea_reason = sea.assessed? ? nil : sea.reason

      (1..12).each do |month|
        stats = air_by_month[month]
        next if stats.nil?

        sea_temp = sea_by_month[month]
        unassessed = {}
        if sea_temp.nil?
          unassessed["sea_temp_c"] = sea_reason ||
                                     "no sea surface temperature at this location — it is not on a coast"
        end

        record = DestinationClimateNormalRecord.find_or_initialize_by(city_code: destination.city_code, month: month)
        record.update!(
          destination_id: destination.id,
          temp_mean_c: stats[:mean], temp_min_c: stats[:min], temp_max_c: stats[:max],
          precipitation_mm: stats[:precipitation_mm], rain_days: stats[:rain_days], sea_temp_c: sea_temp,
          air_years_from: AIR_YEARS.first, air_years_to: AIR_YEARS.last,
          sea_years_from: sea_temp && SEA_FROM.year, sea_years_to: sea_temp && Date.today.year,
          source: "open-meteo", unassessed: unassessed, computed_at: Time.now.utc
        )
        summary.months += 1
        summary.with_sea += 1 if sea_temp
      end

      log&.call("#{destination.city_code}: 12 months#{sea_by_month.empty? ? " (no sea temperature)" : ""}")
    end

    # Mean of daily values per calendar month across the window. Precipitation is summed per year-month first,
    # because a monthly total is what a reader pictures.
    def monthly_air(daily)
      buckets = Hash.new { |hash, key| hash[key] = { mean: [], min: [], max: [], wet: 0, days: 0 } }
      yearly_precipitation = Hash.new(0.0)

      daily["time"].each_with_index do |iso, index|
        date = Date.parse(iso)
        bucket = buckets[date.month]
        bucket[:mean] << daily["temperature_2m_mean"][index]
        bucket[:min] << daily["temperature_2m_min"][index]
        bucket[:max] << daily["temperature_2m_max"][index]

        precipitation = daily["precipitation_sum"][index]
        next if precipitation.nil?

        bucket[:days] += 1
        bucket[:wet] += 1 if precipitation >= RAIN_DAY_MM
        yearly_precipitation[[date.year, date.month]] += precipitation
      end

      buckets.to_h do |month, bucket|
        totals = yearly_precipitation.select { |(_, m), _| m == month }.values
        years = (daily["time"].empty? ? 1 : [totals.length, 1].max)

        [month, {
          mean: average(bucket[:mean]), min: average(bucket[:min]), max: average(bucket[:max]),
          precipitation_mm: totals.empty? ? nil : (totals.sum / totals.length).round(1),
          # Days per month, not per window: the count is scaled back by however many years contributed.
          rain_days: bucket[:days].zero? ? nil : (bucket[:wet].to_f / years).round(1)
        }]
      end
    end

    def monthly_sea(daily)
      buckets = Hash.new { |hash, key| hash[key] = [] }
      daily["time"].each_with_index do |iso, index|
        value = daily["sea_surface_temperature_mean"][index]
        buckets[Date.parse(iso).month] << value if value
      end
      buckets.filter_map { |month, values| [month, average(values)] if values.any? }.to_h
    end

    def average(values)
      present = values.compact
      return nil if present.empty?

      (present.sum / present.length.to_f).round(1)
    end

    def normals(city_code:, month:)
      record = DestinationClimateNormalRecord.find_by(city_code: city_code, month: month.to_i)
      return nil unless record

      {
        "temp_mean_c" => record.temp_mean_c&.to_f, "temp_min_c" => record.temp_min_c&.to_f,
        "temp_max_c" => record.temp_max_c&.to_f, "rain_days" => record.rain_days&.to_f,
        "precipitation_mm" => record.precipitation_mm&.to_f, "sea_temp_c" => record.sea_temp_c&.to_f,
        # Two windows, named, because they are not the same claim.
        "air_years" => "#{record.air_years_from}–#{record.air_years_to}",
        "sea_years" => (record.sea_years_from && "#{record.sea_years_from}–#{record.sea_years_to}"),
        "rain_day_threshold_mm" => RAIN_DAY_MM,
        "unassessed" => record.unassessed, "source" => record.source, "freshness" => "cached"
      }
    end

    def forecast(city_code:, from:, to:, cache: PageCache.new, offline: false)
      destination = DestinationRecord.find_by(city_code: city_code)
      return [] unless destination

      answer = OpenMeteo.forecast(lat: destination.lat, lon: destination.lon, from: from, to: to,
                                  cache: cache, offline: offline)
      unless answer.assessed?
        return [{ "date" => from.to_s, "freshness" => "cached", "unassessed" => { "all" => answer.reason } }]
      end

      freshness = answer.from_cache ? "cached" : "live"
      answer.daily["time"].each_with_index.map do |iso, index|
        {
          "date" => iso,
          "temp_mean_c" => answer.daily["temperature_2m_mean"][index],
          "temp_min_c" => answer.daily["temperature_2m_min"][index],
          "temp_max_c" => answer.daily["temperature_2m_max"][index],
          "precipitation_mm" => answer.daily["precipitation_sum"][index],
          "precipitation_probability" => answer.daily["precipitation_probability_mean"][index],
          "freshness" => freshness
        }
      end
    end

    def destinations(city_codes)
      scope = DestinationRecord.order(:city_code)
      city_codes ? scope.where(city_code: city_codes) : scope
    end
  end
end
