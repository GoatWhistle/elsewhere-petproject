require "rails_helper"

RSpec.describe "Phase 0 walking skeleton", type: :request do
  let(:dream) do
    {
      dream_text: "Тёплое море, тихо, вкусно, до 180000 ₽",
      origin: "MOW",
      date_window: { earliest: "2026-07-01", latest: "2026-07-31", nights_min: 6, nights_max: 7 },
      party: { adults: 2 }
    }
  end

  it "walks session → jobs → futures → simulation → forecast through Rails HTTP" do
    post "/planning-sessions", params: dream, as: :json
    expect(response).to have_http_status(:created)
    session = response.parsed_body
    expect(session.dig("travel_dna", "elements").map { |item| item["dimension"] }).to include("sea_access")
    expect(PlanningSessionRecord.count).to eq(1)

    all_elements = session.dig("travel_dna", "elements")
    confirmed = all_elements.select { |element| element["weight"] }.first(2)
    patch "/planning-sessions/#{session.fetch("id")}/travel-dna", params: { elements: confirmed }, as: :json
    expect(response).to have_http_status(:ok)
    get "/planning-sessions/#{session.fetch("id")}"
    # PATCH is an upsert by dimension (B-2): editing two elements confirms those two and erases none of the
    # rest. Phase 0's stub replaced the whole set, and this assertion used to encode that.
    updated = response.parsed_body.dig("travel_dna", "elements")
    expect(updated.size).to eq(all_elements.size)
    expect(updated.select { |element| element["provenance"] == "confirmed" }.size).to eq(2)

    post "/planning-sessions/#{session.fetch("id")}/futures", as: :json
    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body.fetch("status")).to eq("succeeded")
    expect(JobRecord.count).to eq(1)

    get "/planning-sessions/#{session.fetch("id")}/futures"
    futures = response.parsed_body.fetch("futures")
    # Two, not three, and the note says why: Sochi is the one destination Ignav really covers, and its fare
    # comes back in USD while the room rate is modeled in RUB. Summing them needs an exchange rate, and whose
    # number that is has not been decided — so the candidate is refused rather than invented. When that lands,
    # this becomes three.
    expect(futures.size).to eq(2)
    expect(response.parsed_body.fetch("diversity_note")).to include("разные валюты")
    future = futures.first
    expect(future.dig("logistics", "outbound")).to be_present
    expect(future.dig("match", "contributions")).to be_present
    expect(future.dig("price", "components").find { |component| component["kind"] == "accommodation" }.fetch("fulfilment")).to eq("modeled")
    expect(FutureVersionRecord.count).to eq(2)

    post "/futures/#{future.fetch("id")}/simulations", params: { instruction: "Сделай дешевле" }, as: :json
    expect(response).to have_http_status(:accepted)
    simulated = response.parsed_body.dig("result", "future")
    expect(simulated.fetch("parent_id")).to eq(future.fetch("id"))
    expect(simulated.dig("delta", "items")).to be_present
    expect(JobRecord.count).to eq(2)

    get "/futures/#{future.fetch("id")}/forecast"
    expect(response).to have_http_status(:ok)
    forecast = response.parsed_body
    expect(forecast.fetch("risks")).to all(include("evidence", "claim_kind"))
    expect(forecast.fetch("coverage")).to include(include("assessed" => false, "reason" => a_kind_of(String)))
  end
end
