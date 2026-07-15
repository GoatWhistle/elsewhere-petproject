require "rails_helper"

RSpec.describe "Supply freshness" do
  it "labels every fixture read" do
    expect(Supply::Catalog.destinations).to all(have_attributes(freshness: "fixture"))
    expect(Supply::Catalog.properties(city_code: "AER", limit: 10)).to all(have_attributes(freshness: "fixture"))
    expect(Supply::Rates.for(property_id: "prop-sochi-sea", check_in: "2026-07-08", check_out: "2026-07-15", adults: 2)).to include("basis" => "modeled", "freshness" => "fixture")
    expect(Supply::Flights.price(origin: "MOW", destination: "AER", depart_on: "2026-07-08", return_on: "2026-07-15", adults: 2)).to include("freshness" => "fixture")
    expect(Supply::Flights.around_dates(origin: "MOW", destination: "AER", depart_on: "2026-07-08", window_days: 3)).to all(include("freshness" => "fixture"))
    expect(Supply::Geo.features(property_id: "prop-sochi-sea")).to include("freshness" => "fixture")
    expect(Supply::Climate.normals(city_code: "AER", month: 7)).to include("freshness" => "fixture")
    expect(Supply::Climate.forecast(city_code: "AER", from: "2026-07-08", to: "2026-07-15")).to all(include("freshness" => "fixture"))
    expect(Supply::Reviews.for_property(property_id: "prop-sochi-sea").freshness).to eq("fixture")
  end
end
