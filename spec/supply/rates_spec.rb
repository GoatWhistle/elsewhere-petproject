require "rails_helper"

RSpec.describe Supply::RateModel do
  # The 84 calibration rows the model actually produced for the corpus. Asserting the guards against invented
  # numbers would prove nothing about the rates this product will print.
  let(:real) { JSON.parse(Rails.root.join("packs/supply/fixtures/price_calibrations.json").read) }

  describe "the guards DEC-029 asks for" do
    it "keeps the factor inside its bounds for every corpus destination and month" do
      factors = real.map { |row| row["seasonal_factor"] }

      expect(real.length).to eq(84)                      # seven destinations, twelve months
      expect(factors.min).to be >= described_class::FACTOR_MIN
      expect(factors.max).to be <= described_class::FACTOR_MAX
    end

    it "is monotone in the seasonal signal: more comfort is never cheaper" do
      real.group_by { |row| row["city_code"] }.each_value do |rows|
        by_comfort = rows.sort_by { |row| row["comfort"] }

        expect(by_comfort.map { |row| row["seasonal_factor"] }).to eq(by_comfort.map { |row| row["seasonal_factor"] }.sort)
      end
    end

    it "puts the high season where the destination actually has one" do
      peak = ->(code) { real.select { |row| row["city_code"] == code }.max_by { |row| row["seasonal_factor"] }["month"] }

      expect(peak.call("AER")).to be_between(7, 9)   # the Black Sea in summer
      expect(peak.call("LED")).to be_between(6, 8)
      expect(peak.call("NOZ")).to be_between(12, 12).or be_between(1, 2)  # a ski resort in winter
    end

    it "carries the reason the number is what it is, not just the number" do
      row = real.first

      expect(row["inputs"]).to include("temp_mean_c", "peak_season", "reviews_per_property")
      expect(row["inputs"]["basis"]).to eq("the base is observed; this seasonality is modeled")
    end
  end

  describe "the rate" do
    let(:destination) do
      DestinationRecord.create!(city_code: "AER", name: "Сочи", country: "Россия", lat: 43.58, lon: 39.72,
                                source: "101hotels", source_slug: "sochi", geography_type: "sea",
                                peak_season: "warm", centre_source: "osm_place")
    end
    let(:property) do
      PropertyRecord.create!(catalogue_id: "101hotels:1", source: "101hotels", destination: destination,
                             city_code: "AER", name: "У моря", lat: 43.58, lon: 39.72,
                             price_level_minor: 520_000, price_currency: "RUB",
                             source_url: "https://101hotels.com/x.html", harvested_at: Time.current)
    end

    def calibrate(month, factor)
      PriceCalibrationRecord.create!(city_code: "AER", month: month, model_version: described_class::VERSION,
                                     seasonal_factor: factor, comfort: 0.9, popularity: 0.5, amplitude: 0.3,
                                     inputs: {}, computed_at: Time.current)
    end

    before do
      property
      calibrate(8, 1.281)
      calibrate(9, 1.194)
    end

    it "is the observed base times the factor times the nights, and says so" do
      rate = described_class.for(property_id: "101hotels:1", check_in: "2026-08-01", check_out: "2026-08-08")

      expect(rate["amount"]).to eq("amount_minor" => (520_000 * 1.281).round * 7, "currency" => "RUB")
      expect(rate["basis"]).to eq("modeled")
      expect(rate["calibration"]).to include("model_version" => described_class::VERSION,
                                             "observed_base_minor" => 520_000,
                                             "statement" => "the base is observed; the seasonality is modeled")
      expect(rate["explanation"]["seasonal_change_pct"]).to eq(28)
      expect(rate["handoff_url"]).to eq("https://101hotels.com/x.html")
    end

    it "gives the same answer every time, or a Simulator delta is noise" do
      first = described_class.for(property_id: "101hotels:1", check_in: "2026-08-01", check_out: "2026-08-08")
      second = described_class.for(property_id: "101hotels:1", check_in: "2026-08-01", check_out: "2026-08-08")

      expect(first).to eq(second)
    end

    it "prices a stay that crosses a month one night at a time, not wholesale" do
      rate = described_class.for(property_id: "101hotels:1", check_in: "2026-08-30", check_out: "2026-09-02")

      expect(rate["explanation"]["per_night"].map { |night| night["factor"] }).to eq([1.281, 1.281, 1.194])
      expect(rate["amount"]["amount_minor"])
        .to eq((520_000 * 1.281).round * 2 + (520_000 * 1.194).round)
    end

    it "says the base is per room rather than silently pricing a party" do
      rate = described_class.for(property_id: "101hotels:1", check_in: "2026-08-01", check_out: "2026-08-08",
                                 adults: 3)

      expect(rate["unassessed"]["occupancy"]).to include("per room")
    end
  end

  describe "when the base is missing" do
    it "returns no amount and the reason, rather than a rate resting on nothing" do
      destination = DestinationRecord.create!(city_code: "AER", name: "Сочи", country: "Россия", lat: 43.5,
                                              lon: 39.7, source: "101hotels", source_slug: "sochi",
                                              geography_type: "sea", peak_season: "warm")
      PropertyRecord.create!(catalogue_id: "101hotels:2", source: "101hotels", destination: destination,
                             city_code: "AER", name: "Без цены", lat: 43.5, lon: 39.7,
                             price_level_note: "the listing publishes no price",
                             source_url: "https://example.invalid", harvested_at: Time.current)

      rate = described_class.for(property_id: "101hotels:2", check_in: "2026-08-01", check_out: "2026-08-08")

      expect(rate["amount"]).to be_nil
      expect(rate["basis"]).to eq("modeled")
      expect(rate["unassessed"]["amount"]).to eq("the listing publishes no price")
    end
  end
end
