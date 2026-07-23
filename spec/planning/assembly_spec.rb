require "rails_helper"

RSpec.describe Planning::Assembly do
  let(:window) { { "earliest" => "2026-07-01", "latest" => "2026-07-31" } }
  let(:session) do
    Planning::Sessions.create(dream_text: "Вдвоём на неделю к тёплому морю, тихо, вкусно, до 180000 ₽",
                              origin: "MOW", date_window: window, party: { "adults" => 2 })
  end
  let(:generated) { Planning::Futures.generate(session_id: session.fetch("id")) }
  let(:future) { generated.fetch("futures").first }

  describe "a Future is a whole trip" do
    it "has legs, a stay, a transfer and a mobility assumption" do
      logistics = future.fetch("logistics")

      expect(logistics.dig("outbound", "origin")).to eq("MOW")
      expect(logistics.dig("inbound", "destination")).to eq("MOW")
      expect(logistics.dig("outbound", "duration_min")).to be_a(Integer)
      expect(logistics.dig("airport_transfer", "mode")).to be_present
      expect(logistics.dig("local_mobility", "assumption")).to be_present
    end

    it "picks its own dates inside the user's window" do
      expect(Date.parse(future.fetch("check_in"))).to be >= Date.parse(window.fetch("earliest"))
      expect(Date.parse(future.fetch("check_out"))).to be <= Date.parse(window.fetch("latest"))
      expect(future.fetch("check_in")).not_to eq("2026-07-08")  # the stub's literal
    end

    it "carries a fare's observation time on the leg" do
      expect(future.dig("logistics", "outbound", "as_of")).to be_present
    end
  end

  describe "every component says where its number came from" do
    it "marks the room rate modeled, and the fare by whether it was actually observed" do
      components = future.dig("price", "components").to_h { |c| [c["kind"], c] }

      expect(components["accommodation"]["fulfilment"]).to eq("modeled")
      expect(components["accommodation"]["source"]).to include("observed base level")

      # These two destinations have no captured Ignav fare, so their travel component is a placeholder and says
      # so. Calling a number nobody observed an "estimate" is the one dishonest move available here.
      expect(components["travel"]["fulfilment"]).to eq("modeled")
      expect(components["travel"]["as_of"]).to be_nil
      expect(components["travel"]["source"]).to include("заглушка")
    end

    it "marks a fare that really was observed as an estimate, with its observation time" do
      fare = Supply::Flights.price(origin: "MOW", destination: "AER", depart_on: "2026-07-08",
                                   return_on: "2026-07-15", adults: 2)
      component = described_class.travel_component(fare)

      expect(fare["basis"]).to eq("observed")
      expect(component["fulfilment"]).to eq("estimate")
      expect(component["as_of"]).to be_present
    end

    it "omits the transfer and mobility costs rather than inventing them" do
      kinds = future.dig("price", "components").map { |c| c["kind"] }

      # Supply publishes no transfer or local-mobility model in this build. The stub filled both in with two
      # magic numbers per city; absent and stated is the honest version.
      expect(kinds).to contain_exactly("travel", "accommodation")
      expect(future.dig("logistics", "airport_transfer", "note")).to include("не моделируются")
    end

    it "totals exactly the components it lists" do
      total = future.dig("price", "components").sum { |c| c["amount"]["amount_minor"] }

      expect(future.dig("price", "total", "amount_minor")).to eq(total)
    end
  end

  describe "the fare budget" do
    it "is bounded per generation" do
      budget = described_class::Budget.new(fare_requests: [])
      allow(described_class).to receive(:assemble).and_wrap_original do |original, *args, **kwargs|
        original.call(*args, **kwargs.merge(budget: budget))
      end

      Planning::Futures.generate(session_id: session.fetch("id"))

      expect(budget.fare_requests.length).to be <= Planning::Futures::FARE_BUDGET
    end

    it "asks once per destination and date pair, not once per property" do
      fares = {}
      budget = described_class::Budget.new(fare_requests: [])
      constraints = Planning::Constraints.from(Planning::DnaStore.find(session.fetch("id")),
                                               date_window: window, party: { "adults" => 2 })
      dna = Planning::DnaStore.find(session.fetch("id"))
      shortlist = Planning::Candidates.shortlist(dna, constraints, months: [7])
      sochi = shortlist.select { |candidate| candidate.destination.city_code == "AER" }

      expect(sochi.length).to be >= 2   # more than one property in the same destination
      sochi.each do |candidate|
        described_class.assemble(candidate, constraints, origin: "MOW", party: { "adults" => 2 },
                                                         fares: fares, budget: budget)
      end

      expect(budget.fare_requests.map { |key| key.first(2) }.uniq.length).to eq(1)
      expect(budget.fare_requests.length).to be <= described_class::MAX_DATE_PAIRS
    end

    it "tries at most a couple of date pairs, because each one costs a request" do
      constraints = Planning::Constraints.from({ "elements" => [] }, date_window: window)

      expect(described_class.date_pairs(constraints, nights: 7).length).to eq(described_class::MAX_DATE_PAIRS)
    end
  end

  describe "two currencies in one trip" do
    it "is refused rather than summed with an invented rate" do
      expect(generated.fetch("futures")).to be_present
      note = Planning::Futures.list(session_id: session.fetch("id"))["diversity_note"]

      expect(note).to include("разные валюты")
      expect(generated.fetch("futures").map { |f| f.dig("price", "total", "currency") }.uniq).to eq(["RUB"])
    end
  end
end
