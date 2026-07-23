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
    # One, not three, and the note accounts for every missing option rather than leaving the set unexplained.
    # Sochi is the one destination Ignav really covers and its fare comes back in USD while the room rate is
    # modeled in RUB, so both Sochi candidates are refused rather than summed with an invented exchange rate.
    # Of what remains, Saint Petersburg sits 0.13 of match below the best — below archetype C's floor — and
    # padding the set with it would be dishonest. Each of those is a decision this suite is pinning, not an
    # accident; when the FX question is answered the count changes and this changes with it.
    expect(futures.size).to eq(1)
    note = response.parsed_body.fetch("diversity_note")
    expect(note).to include("разные валюты")
    expect(note).to include("не дотягивает до порога")
    future = futures.first
    expect(future.dig("logistics", "outbound")).to be_present
    expect(future.dig("match", "contributions")).to be_present
    expect(future.dig("price", "components").find { |component| component["kind"] == "accommodation" }.fetch("fulfilment")).to eq("modeled")
    expect(FutureVersionRecord.count).to eq(1)

    post "/futures/#{future.fetch("id")}/simulations", params: { instruction: "Сделай дешевле" }, as: :json
    expect(response).to have_http_status(:accepted)
    result = response.parsed_body.fetch("result")

    # On this corpus there is nothing cheaper to move to, and the simulator says so instead of handing back a
    # version identical to its parent. Both branches are walked here because both are real answers.
    if result.fetch("kind") == "future"
      simulated = result.fetch("future")
      expect(simulated.fetch("parent_id")).to eq(future.fetch("id"))
      expect(simulated.dig("delta", "items").sum { |item| item.dig("amount", "amount_minor") })
        .to eq(simulated.dig("delta", "price_change", "amount_minor"))
    else
      expect(result.fetch("kind")).to eq("no_solution")
      expect(result.dig("no_solution", "reason")).to be_present
      expect(result.dig("no_solution", "unsatisfiable_constraints")).to be_present
    end
    expect(JobRecord.count).to eq(2)

    get "/futures/#{future.fetch("id")}/forecast"
    expect(response).to have_http_status(:ok)
    forecast = response.parsed_body
    expect(forecast.fetch("risks")).to all(include("evidence", "claim_kind"))
    expect(forecast.fetch("coverage")).to include(include("assessed" => false, "reason" => a_kind_of(String)))
  end
end
