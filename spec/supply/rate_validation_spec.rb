require "rails_helper"

RSpec.describe Supply::RateValidation do
  # The real thing on both sides: the 84 calibration rows the model produced, and the observed price levels the
  # harvest actually collected. Validating the model against invented numbers would prove nothing about it.
  let(:calibrations) { JSON.parse(Rails.root.join("packs/supply/fixtures/price_calibrations.json").read) }
  let(:price_levels) do
    JSON.parse(Rails.root.join("packs/supply/fixtures/corpus_profile.json").read)
        .to_h { |city| [city["city_code"], city["price_levels_minor"]] }
  end
  let(:report) { described_class.report(calibrations: calibrations, price_levels: price_levels) }

  it "passes every defensibility check on the real corpus" do
    failed = report["checks"].reject { |check| check["passed"] }

    expect(failed).to be_empty, -> { failed.map { |check| "#{check["name"]}: #{check["detail"]}" }.join("\n") }
    expect(report["passed"]).to be(true)
    expect(report["destinations"].length).to eq(7)
  end

  it "keeps every modeled rate inside the corridor DEC-029 declared" do
    check = report["checks"].find { |entry| entry["name"] == "anchored to the observed base" }

    expect(check["passed"]).to be(true)
    expect(check["detail"]).to include("84 factors")
  end

  it "neither inflates nor deflates the harvest over a year" do
    means = calibrations.group_by { |row| row["city_code"] }.transform_values do |rows|
      factors = rows.map { |row| row["seasonal_factor"] }
      factors.sum / factors.length
    end

    means.each_value { |mean| expect(mean).to be_within(described_class::BIAS_TOLERANCE).of(1.0) }
  end

  it "leaves a season worth shifting between, or 'change your dates' is decorative" do
    check = report["checks"].find { |entry| entry["name"] == "a season worth shifting" }

    expect(check["passed"]).to be(true)
    expect(check["detail"]).to include("AER ×1.78")
  end

  # A validation that cannot fail proves nothing, so each check is shown catching the thing it is for.
  describe "each check can actually fail" do
    def broken(rows) = described_class.report(calibrations: rows, price_levels: price_levels)

    def check(report, name) = report["checks"].find { |entry| entry["name"] == name }

    it "catches a factor that leaves the declared bounds" do
      rows = calibrations.map(&:dup)
      rows.first["seasonal_factor"] = 2.4

      expect(check(broken(rows), "anchored to the observed base")["passed"]).to be(false)
    end

    it "catches a model that quietly restates every harvested price" do
      rows = calibrations.map { |row| row.merge("seasonal_factor" => row["seasonal_factor"] * 1.2) }

      expect(check(broken(rows), "unbiased over a year")["passed"]).to be(false)
    end

    it "catches a flat model with no season in it" do
      rows = calibrations.map { |row| row.merge("seasonal_factor" => 1.0) }

      expect(check(broken(rows), "a season worth shifting")["passed"]).to be(false)
    end

    it "catches a model that reorders the corpus" do
      rows = calibrations.map { |row| row.merge("seasonal_factor" => -1.0) }

      expect(check(broken(rows), "order of the corpus preserved")["passed"]).to be(false)
    end
  end

  # OQ-A's "calibrated on the price levels observed for *that* property, not a global formula" is checked here
  # rather than in the report, because in the report it could not fail: with rate = base × factor it is
  # arithmetic. End to end through two real properties it can — a city average instead of the property's own
  # observed level would break it immediately.
  describe "the base is the property's own, not the city's" do
    it "gives two properties in one city rates in the ratio of their observed levels" do
      dear = Supply::Catalog.property(id: "prop-sochi-sea")
      cheap = Supply::Catalog.property(id: "prop-sochi-quiet")
      dates = { check_in: "2026-07-08", check_out: "2026-07-15", adults: 2 }

      dear_rate = Supply::Rates.for(property_id: dear.catalogue_id, **dates)["amount"]["amount_minor"]
      cheap_rate = Supply::Rates.for(property_id: cheap.catalogue_id, **dates)["amount"]["amount_minor"]

      expect(dear.price_level).to be > cheap.price_level
      expect(dear_rate.to_f / cheap_rate).to be_within(0.001).of(dear.price_level.to_f / cheap.price_level)
    end
  end

  describe "what this cannot check" do
    it "does not claim the seasonality itself was verified" do
      # The base is observed; the seasonality is a hypothesis, and no free source has dated prices to test it
      # against (DEC-016), nor did the lead want them collected by hand (DEC-029). Saying so is the honest part.
      rate = Supply::Rates.for(property_id: "prop-sochi-sea", check_in: "2026-07-08", check_out: "2026-07-15",
                               adults: 2)

      expect(rate["basis"]).to eq("modeled")
      expect(described_class.report(calibrations: calibrations, price_levels: price_levels))
        .not_to have_key("seasonality_verified")
    end
  end
end
