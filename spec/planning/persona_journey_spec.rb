require "rails_helper"

# The persona suite is the product's real test, so it is walked through the HTTP layer rather than
# the domain objects: every response is validated against the frozen contract, and every Future is checked
# against the hard constraints its own Dream produced.
RSpec.describe "Persona journeys", type: :request do
  let(:document) { YAML.safe_load(Rails.root.join("docs/04_api/openapi.yaml").read, aliases: true) }
  let(:personas) { JSON.parse(Rails.root.join("spec/fixtures/personas/demo_ru.json").read) }
  let(:window) { { earliest: "2026-07-01", latest: "2026-07-31", nights_min: 6, nights_max: 7 } }

  def conform!(payload, schema_name)
    schema = document.fetch("components").fetch("schemas").fetch(schema_name)
    Elsewhere::Schema.validate!(payload, schema, root: document, path: schema_name)
  end

  def walk(persona)
    post "/planning-sessions",
         params: { dream_text: persona.fetch("dream"), origin: "MOW", date_window: window, party: { adults: 2 } },
         as: :json
    expect(response).to have_http_status(:created)
    session = response.parsed_body
    conform!(session, "PlanningSession")

    post "/planning-sessions/#{session.fetch("id")}/futures", as: :json
    expect(response).to have_http_status(:accepted)

    get "/planning-sessions/#{session.fetch("id")}/futures"
    expect(response).to have_http_status(:ok)
    [session, response.parsed_body]
  end

  it "gives every persona a session whose DNA is theirs and conforms to the contract" do
    shapes = personas.map do |persona|
      session, = walk(persona)
      dimensions = session.dig("travel_dna", "elements").map { |element| element["dimension"] }

      expect(dimensions).to include(*persona.fetch("must_include"))
      session.fetch("clarifications").each { |clarification| conform!(clarification, "Clarification") }
      dimensions.sort
    end

    expect(shapes.uniq.length).to eq(10)
  end

  it "returns only Futures that conform, and only Futures that satisfy their own hard constraints" do
    personas.each do |persona|
      session, listing = walk(persona)
      constraints = Planning::Constraints.from(Planning::DnaStore.find(session.fetch("id")),
                                               date_window: window.transform_keys(&:to_s),
                                               party: { "adults" => 2 })

      listing.fetch("futures").each do |future|
        conform!(future, "Future")
        expect(Planning::Constraints.violations(future, constraints)).to be_empty,
                                                                         "#{persona["id"]}: #{future.dig("destination", "city_code")}"
      end
    end
  end

  it "explains every set that is not three, and never pads one that is" do
    personas.each do |persona|
      _, listing = walk(persona)
      futures = listing.fetch("futures")

      expect(futures.length).to be <= 3
      expect(listing["diversity_note"]).to be_present if futures.length < 3
      expect(futures.map { |future| future.fetch("id") }.uniq.length).to eq(futures.length)
    end
  end

  it "gives every Future a decomposition that adds up and an honest coverage" do
    personas.each do |persona|
      _, listing = walk(persona)

      listing.fetch("futures").each do |future|
        match = future.fetch("match")
        weight = match.fetch("contributions").sum { |c| c.fetch("weight") }
        total = match.fetch("contributions").sum { |c| c.fetch("contribution") }

        expect((total / weight).clamp(0.0, 1.0).round(4)).to eq(match.fetch("score"))
        expect(match.fetch("confidence")).to be <= match.fetch("coverage")
        match.fetch("unscored_dimensions").each { |gap| expect(gap.fetch("reason")).to be_present }
      end
    end
  end

  it "prices every component with its provenance, and totals exactly what it lists" do
    personas.first(4).each do |persona|
      _, listing = walk(persona)

      listing.fetch("futures").each do |future|
        components = future.dig("price", "components")
        expect(components).to be_present
        expect(components.map { |c| c.fetch("fulfilment") }).to all(be_in(%w[estimate modeled]))
        expect(future.dig("price", "total", "amount_minor")).to eq(components.sum { |c| c.dig("amount", "amount_minor") })
        expect(components.map { |c| c.dig("amount", "currency") }.uniq.length).to eq(1)
      end
    end
  end

  it "forecasts each Future with evidence, and simulates it without ever mutating it" do
    _, listing = walk(personas.first)
    future = listing.fetch("futures").first

    get "/futures/#{future.fetch("id")}/forecast"
    expect(response).to have_http_status(:ok)
    conform!(response.parsed_body, "Forecast")
    response.parsed_body.fetch("risks").each { |risk| expect(risk.fetch("evidence")).to be_present }

    before = Planning::Futures.find(future_id: future.fetch("id"))
    post "/futures/#{future.fetch("id")}/simulations", params: { instruction: "Сделай дешевле" }, as: :json
    expect(response).to have_http_status(:accepted)
    conform!(response.parsed_body, "Job")

    expect(Planning::Futures.find(future_id: future.fetch("id"))).to eq(before)
  end
end
