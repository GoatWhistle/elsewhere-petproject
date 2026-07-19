require "rails_helper"
require "tmpdir"

RSpec.describe Supply::ClimateData do
  let(:destination) do
    DestinationRecord.create!(city_code: "AER", name: "Сочи", country: "Россия", lat: 43.5855, lon: 39.7231,
                              source: "101hotels", source_slug: "sochi", geography_type: "sea",
                              centre_source: "osm_place")
  end

  # Real captured Open-Meteo answers (assumption A-007), two years of them, placed in the cache the way a real
  # refresh leaves them — so the whole aggregation runs without touching the network.
  def cache_with_real_answers(marine: true)
    cache = Supply::PageCache.new(root: Dir.mktmpdir("climate-spec"))
    archive_url = url_for(Supply::OpenMeteo::ARCHIVE,
                          start_date: "#{Supply::ClimateData::AIR_YEARS.first}-01-01",
                          end_date: "#{Supply::ClimateData::AIR_YEARS.last}-12-31",
                          daily: Supply::OpenMeteo::DAILY.join(","), timezone: "UTC")
    cache.write(archive_url, status: 200, body: fixture("archive_sochi_2023_2024.json"))

    if marine
      marine_url = url_for(Supply::OpenMeteo::MARINE, start_date: Supply::ClimateData::SEA_FROM.to_s,
                                                      end_date: (Date.today - 7).to_s,
                                                      daily: "sea_surface_temperature_mean", timezone: "UTC")
      cache.write(marine_url, status: 200, body: fixture("marine_sochi_2024.json"))
    end
    cache
  end

  def url_for(endpoint, **params)
    all = { latitude: destination.lat, longitude: destination.lon }.merge(params)
    "#{endpoint}?#{URI.encode_www_form(all.sort_by { |key, _| key.to_s })}"
  end

  def fixture(name) = Rails.root.join("packs/supply/fixtures/open_meteo", name).read

  describe "normals" do
    before { described_class.refresh!(cache: cache_with_real_answers, offline: true) }

    it "answers for every month of a corpus destination, from real measurements" do
      expect(DestinationClimateNormalRecord.where(city_code: "AER").count).to eq(12)

      july = described_class.normals(city_code: "AER", month: 7)
      expect(july["temp_mean_c"]).to be_between(20, 28)
      expect(july["temp_min_c"]).to be < july["temp_mean_c"]
      expect(july["temp_max_c"]).to be > july["temp_mean_c"]
      expect(july["sea_temp_c"]).to be_between(20, 30)
      expect(july["freshness"]).to eq("cached")
    end

    it "is colder in January than in July, which is the least a climate normal owes anyone" do
      january = described_class.normals(city_code: "AER", month: 1)
      july = described_class.normals(city_code: "AER", month: 7)

      expect(january["temp_mean_c"]).to be < july["temp_mean_c"]
      expect(january["sea_temp_c"]).to be < july["sea_temp_c"]
      expect(january["rain_days"]).to be > july["rain_days"]
    end

    it "counts rain days per month, and says what a rain day is" do
      january = described_class.normals(city_code: "AER", month: 1)

      expect(january["rain_days"]).to be_between(0, 31)
      expect(january["rain_day_threshold_mm"]).to eq(1.0)
    end

    it "names the two windows separately, because thirty years of air and three of sea are not one claim" do
      july = described_class.normals(city_code: "AER", month: 7)

      expect(july["air_years"]).to eq("#{Supply::ClimateData::AIR_YEARS.first}–#{Supply::ClimateData::AIR_YEARS.last}")
      expect(july["sea_years"]).to start_with(Supply::ClimateData::SEA_FROM.year.to_s)
      expect(july["air_years"]).not_to eq(july["sea_years"])
    end
  end

  describe "inland, where there is no sea to measure" do
    it "reports the absence with a reason instead of leaving a hole" do
      described_class.refresh!(cache: cache_with_real_answers(marine: false), offline: true)

      july = described_class.normals(city_code: "AER", month: 7)
      expect(july["sea_temp_c"]).to be_nil
      expect(july["unassessed"]["sea_temp_c"]).to be_present
      expect(july["sea_years"]).to be_nil
    end
  end

  describe "a destination with no normals yet" do
    it "says so rather than answering" do
      answer = Supply::Sources::DatabaseClimate.normals(city_code: "ZZZ", month: 7)

      expect(answer["unassessed"]["all"]).to include("no normals computed")
    end
  end

  describe "the forecast, which is the one answer that goes stale" do
    let(:cache) { Supply::PageCache.new(root: Dir.mktmpdir("forecast-spec")) }
    let(:body) do
      JSON.generate("daily" => { "time" => ["2026-07-08"], "temperature_2m_mean" => [24.1],
                                 "temperature_2m_min" => [20.0], "temperature_2m_max" => [28.0],
                                 "precipitation_sum" => [0.0], "precipitation_probability_mean" => [5] })
    end

    before { destination }

    it "is labelled cached while it is fresh" do
      url = url_for(Supply::OpenMeteo::FORECAST, start_date: "2026-07-08", end_date: "2026-07-08",
                                                 daily: Supply::OpenMeteo::FORECAST_DAILY.join(","), timezone: "auto")
      cache.write(url, status: 200, body: body)

      days = described_class.forecast(city_code: "AER", from: "2026-07-08", to: "2026-07-08",
                                      cache: cache, offline: true)

      expect(days.first).to include("temp_mean_c" => 24.1, "freshness" => "cached")
    end

    it "treats an entry past its maximum age as a miss, not as a current answer" do
      url = url_for(Supply::OpenMeteo::FORECAST, start_date: "2026-07-08", end_date: "2026-07-08",
                                                 daily: Supply::OpenMeteo::FORECAST_DAILY.join(","), timezone: "auto")
      cache.write(url, status: 200, body: body)
      allow(Time).to receive(:now).and_return(Time.now + Supply::OpenMeteo::FORECAST_MAX_AGE_S + 60)

      days = described_class.forecast(city_code: "AER", from: "2026-07-08", to: "2026-07-08",
                                      cache: cache, offline: true)

      expect(days.first["unassessed"]["all"]).to include("not cached, and offline")
    end
  end
end
