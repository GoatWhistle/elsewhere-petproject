require "rails_helper"
require "tmpdir"

RSpec.describe "Supply::Flights" do
  describe "fixture mode, from real captured Ignav answers" do
    it "returns an observed fare with everything needed to judge it" do
      fare = Supply::Flights.price(origin: "VKO", destination: "AER", depart_on: "2026-09-24", adults: 1)

      expect(fare["amount"]).to include("amount_minor" => 12_400, "currency" => "USD")
      expect(fare).to include("basis" => "observed", "freshness" => "fixture", "carrier" => "UTair",
                              "stops" => 0)
      expect(fare["duration_min"]).to eq(230)
      # The provider's own confidence, carried rather than dropped: this one is "unverified" while the pricier
      # connection on the same route is "verified", and a caller may well want to say so.
      expect(fare["price_status"]).to eq("unverified")
      expect(fare["as_of"]).to be_present   # mandatory: a fare is only honest while its age is visible
    end

    it "expands a city code across its airports and takes the best, because one of them is thin" do
      moscow = Supply::Flights.price(origin: "MOW", destination: "AER", depart_on: "2026-09-24", adults: 1)
      sheremetyevo = Supply::Flights.price(origin: "SVO", destination: "AER", depart_on: "2026-09-24", adults: 1)

      # SVO alone would price a 17-hour connection via Abu Dhabi as the Sochi fare.
      expect(sheremetyevo["stops"]).to eq(1)
      expect(sheremetyevo.dig("coverage", "direct_service")).to be(false)
      expect(moscow["stops"]).to eq(0)
      expect(moscow["carrier"]).to eq("UTair")
      expect(moscow.dig("coverage", "origins_tried")).to contain_exactly("DME", "SVO", "VKO")
    end

    it "says when a route has no nonstop at all, rather than leaving the reader to infer it" do
      fare = Supply::Flights.price(origin: "SVO", destination: "AER", depart_on: "2026-09-24", adults: 1)

      expect(fare["coverage"]).to include("assessed" => true, "direct_service" => false, "itineraries" => 2)
      expect(fare["coverage"]["reason"]).to include("no nonstop itinerary")
    end

    it "prices a round trip from the round-trip capture, not by doubling a one-way" do
      one_way = Supply::Flights.price(origin: "LHR", destination: "BCN", depart_on: "2026-09-24")
      round_trip = Supply::Flights.price(origin: "LHR", destination: "BCN", depart_on: "2026-09-24",
                                         return_on: "2026-10-01")

      expect(round_trip["amount"]["amount_minor"]).to eq(13_000)
      expect(round_trip["amount"]["amount_minor"]).not_to eq(one_way["amount"]["amount_minor"] * 2)
    end

    it "multiplies by the party, and keeps money an integer in minor units" do
      one = Supply::Flights.price(origin: "VKO", destination: "AER", depart_on: "2026-09-24", adults: 1)
      two = Supply::Flights.price(origin: "VKO", destination: "AER", depart_on: "2026-09-24", adults: 2)

      expect(two["amount"]["amount_minor"]).to eq(one["amount"]["amount_minor"] * 2)
      expect(two["amount"]["amount_minor"]).to be_a(Integer)
    end

    it "marks a route it never captured as a placeholder, never as an observed fare" do
      fare = Supply::Flights.price(origin: "LED", destination: "KZN", depart_on: "2026-09-24")

      expect(fare["basis"]).to eq("modeled")
      expect(fare["as_of"]).to be_nil
      expect(fare.dig("coverage", "assessed")).to be(false)
      expect(fare.dig("coverage", "reason")).to include("Phase 0 placeholder")
    end

    it "walks a date window without pretending the fares differ by date" do
      days = Supply::Flights.around_dates(origin: "VKO", destination: "AER", depart_on: "2026-09-24",
                                          window_days: 2)

      expect(days.length).to eq(5)
      expect(days.map { |day| day["date"] }).to eq(%w[2026-09-22 2026-09-23 2026-09-24 2026-09-25 2026-09-26])
      expect(days).to all(include("freshness" => "fixture"))
    end
  end

  describe "live mode" do
    let(:cache) { Supply::PageCache.new(root: Dir.mktmpdir("flights-spec")) }

    def cache_answer(url, body)
      cache.write(url, status: 200, body: body)
    end

    def airports_url(query) = "#{Supply::Ignav.base}/airports?q=#{query}&limit=10"

    def fares_url(payload)
      "#{Supply::Ignav.base}/fares/one-way?#{URI.encode_www_form(payload.sort_by { |name, _| name.to_s })}"
    end

    before do
      cache_answer(airports_url("VKO"), JSON.generate([{ "code" => "VKO", "city" => "Moscow", "country" => "RU" }]))
      cache_answer(airports_url("AER"), JSON.generate([{ "code" => "AER", "city" => "Sochi", "country" => "RU" }]))
      cache_answer(fares_url("origin" => "VKO", "destination" => "AER", "departure_date" => "2026-09-24",
                             "adults" => 1, "cabin_class" => "economy"),
                   Rails.root.join("packs/supply/fixtures/ignav/VKO_AER.json").read)
    end

    it "stores every fare it fetches, because fares are the one thing we pay for" do
      fare = Supply::FlightsData.price(origin: "VKO", destination: "AER", depart_on: "2026-09-24", cache: cache)

      expect(fare["basis"]).to eq("observed")
      expect(fare["freshness"]).to eq("live")
      snapshot = FlightFareSnapshotRecord.find_by(origin: "VKO", destination: "AER")
      expect(snapshot).to have_attributes(currency: "USD", stops: 0, direct_service: true, carrier: "UTair")
      expect(snapshot.as_of).to be_present
    end

    it "reads the snapshot on the second ask and spends nothing" do
      Supply::FlightsData.price(origin: "VKO", destination: "AER", depart_on: "2026-09-24", cache: cache)
      again = Supply::FlightsData.price(origin: "VKO", destination: "AER", depart_on: "2026-09-24",
                                        cache: cache, offline: true)

      expect(again["freshness"]).to eq("cached")
      expect(again["amount"]["amount_minor"]).to eq(12_400)
    end

    it "lets no provider failure escape, and says what went wrong instead" do
      empty = Supply::PageCache.new(root: Dir.mktmpdir("flights-empty"))

      answer = Supply::FlightsData.price(origin: "VKO", destination: "AER", depart_on: "2026-09-24",
                                         cache: empty, offline: true)

      expect(answer["amount"]).to be_nil
      expect(answer.dig("coverage", "assessed")).to be(false)
      expect(answer["unassessed"]["amount"]).to be_present
    end

    it "caps the date window, because there is no price calendar and each date costs a request" do
      expect(Supply::FlightsData::MAX_WINDOW_DAYS).to eq(3)

      days = Supply::FlightsData.around_dates(origin: "VKO", destination: "AER", depart_on: "2026-09-24",
                                              window_days: 30, cache: cache, offline: true)

      expect(days.length).to eq(7)
    end
  end
end
