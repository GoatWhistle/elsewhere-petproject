require "rails_helper"

RSpec.describe Foresight::Evidence do
  let(:future) do
    { "accommodation" => { "catalogue_id" => "prop-sochi-sea" },
      "destination" => { "city_code" => "AER" },
      "check_in" => "2026-07-08", "check_out" => "2026-07-15" }
  end
  let(:bundle) { described_class.for_future(future) }

  it "reads geo and climate through Supply, not around it" do
    expect(Supply::Geo).to receive(:features).with(property_id: "prop-sochi-sea").and_call_original
    expect(Supply::Climate).to receive(:normals).with(city_code: "AER", month: 7).and_call_original

    described_class.for_future(future)
  end

  it "uses the climate of the months the stay actually covers" do
    crossing = future.merge("check_in" => "2026-07-28", "check_out" => "2026-08-04")

    expect(described_class.for_future(crossing).months).to eq([7, 8])
    expect(bundle.months).to eq([7])
    expect(bundle.climate_value("temp_mean_c", 7)).to be_present
  end

  describe "the review path, which is the normal one" do
    it "asks Supply for reviews and is told there are none" do
      expect(bundle.reviews.available).to be(false)
      expect(bundle.reviews.reason).to be_present
      expect(bundle.sources["review"]).to include("available" => false)
      expect(bundle.sources["review"]["reason"]).to eq(bundle.reviews.reason)
    end

    it "leaves every review-only risk type unassessable, with Supply's own reason" do
      %w[crowds construction weak_transport room_location_mismatch].each do |risk_type|
        expect(bundle.available?(risk_type)).to be(false)
        expect(bundle.unavailable_reason(risk_type)).to eq(bundle.reviews.reason)
      end
    end
  end

  describe "what the measurements do support" do
    it "knows a type is assessable only when every measurement it needs is present" do
      expect(bundle.available?("night_noise")).to be(true)      # road distance and class
      expect(bundle.available?("walkability")).to be(true)      # poi density and restaurants
      expect(bundle.available?("weather_mismatch")).to be(true) # climate normals for July
      expect(bundle.available?("transfer_difficulty")).to be(true)
    end

    it "treats a missing measurement as missing, never as a zero" do
      allow(Supply::Geo).to receive(:features).and_return("road_class" => "primary", "freshness" => "fixture")

      bundle = described_class.for_future(future)
      expect(bundle.available?("night_noise")).to be(false)
      expect(bundle.unavailable_reason("night_noise")).to include("nearest_major_road_m")
    end

    it "carries the reason Supply gave for a measurement it could not make" do
      allow(Supply::Geo).to receive(:features).and_return(
        "road_class" => "primary", "freshness" => "cached",
        "unassessed" => { "nearest_major_road_m" => "no major road within 5 km" }
      )

      expect(described_class.for_future(future).unavailable_reason("night_noise"))
        .to include("no major road within 5 km")
    end
  end
end
