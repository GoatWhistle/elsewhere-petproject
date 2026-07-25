require "rails_helper"

RSpec.describe "Foresight relevance filtering" do
  # A property that genuinely has all four problems: a road at the door, nothing within a walk, a cold month
  # and a distant airport. Which of them the traveller is told about is the whole question.
  let(:bad_geo) do
    { "nearest_major_road_m" => 40, "road_class" => "primary", "poi_density" => 0.1,
      "restaurant_count_500m" => 1, "airport_distance_m" => 90_000, "freshness" => "cached" }
  end
  let(:cold_july) { { "temp_mean_c" => 8.0, "rain_days" => 18.0, "freshness" => "cached" } }

  # Built from the project's own persona fixtures: `must_include` is the set of dimensions each Dream is
  # supposed to produce, which is exactly what "what this traveller cares about" means here.
  def dna_for_persona(id)
    personas = JSON.parse(Rails.root.join("spec/fixtures/personas/demo_ru.json").read)
    persona = personas.fetch(personas.index { |p| p["id"] == id })
    elements = persona.fetch("must_include").map do |dimension|
      { "dimension" => dimension, "kind" => "preference", "target" => "high", "weight" => 0.9,
        "provenance" => "stated", "confidence" => 0.9 }
    end
    { "id" => "dna-#{id}", "version" => 1, "elements" => elements, "unmatched_intent" => [] }
  end

  def forecast_for(dna)
    future = { "id" => "f1", "session_id" => "s1",
               "accommodation" => { "catalogue_id" => "prop-sochi-sea" },
               "destination" => { "city_code" => "AER" },
               "check_in" => "2026-07-08", "check_out" => "2026-07-15" }
    allow(Planning::Futures).to receive(:find).and_return(future)
    allow(Planning::Sessions).to receive(:find).with(id: "s1").and_return("travel_dna" => dna)
    allow(Supply::Geo).to receive(:features).and_return(bad_geo)
    allow(Supply::Climate).to receive(:normals).and_return(cold_july)

    Foresight::Forecasts.for_future(future_id: "f1")
  end

  it "gives two personas different forecasts for the same property" do
    walkers = forecast_for(dna_for_persona("walkable_food"))   # food_quality, walkability, car_free
    quiet_sea = forecast_for(dna_for_persona("sea_quiet"))     # sea_access, quiet, total_budget

    expect(walkers["risks"].map { |risk| risk["risk_type"] }).to eq(%w[walkability])
    expect(quiet_sea["risks"].map { |risk| risk["risk_type"] }).to eq(%w[night_noise])
    expect(walkers["risks"]).not_to eq(quiet_sea["risks"])
  end

  it "does not warn a nightlife traveller about street noise" do
    nightlife = forecast_for(dna_for_persona("city"))          # nature_vs_city, nightlife, food_quality

    expect(nightlife["risks"]).to be_empty
  end

  it "still reports what it could and could not assess, whoever is asking" do
    forecast = forecast_for(dna_for_persona("city"))
    assessed = forecast["coverage"].select { |entry| entry["assessed"] }.map { |entry| entry["risk_type"] }

    # Filtering changes which risks are shown; it never changes what we claim to have looked at.
    expect(assessed).to contain_exactly("night_noise", "walkability", "weather_mismatch", "transfer_difficulty")
    expect(forecast["coverage"].reject { |entry| entry["assessed"] }).to all(include("reason"))
  end

  describe "what counts as caring about something" do
    it "pins relevance to Planning's normalized weight scale" do
      scale = Planning::Taxonomy::WEIGHT_SCALE

      expect(Planning::DreamParser::LADDER).to all(be_between(scale.begin, scale.end))
      expect(Planning::DreamParser::LADDER_FLOOR).to be_between(scale.begin, scale.end)
      expect(Foresight::Relevance::RELEVANT_WEIGHT)
        .to eq(scale.begin + (scale.end - scale.begin) / 2.0)
    end

    let(:dna) do
      { "elements" => [
        { "dimension" => "quiet", "kind" => "preference", "weight" => 0.9 },
        { "dimension" => "walkability", "kind" => "preference", "weight" => 0.2 },
        { "dimension" => "crowds", "kind" => "aversion", "weight" => 0.1 },
        { "dimension" => "car_free", "kind" => "hard_constraint", "weight" => nil }
      ] }
    end

    it "keeps a heavily weighted preference and drops a barely weighted one" do
      expect(Foresight::Relevance.relevant?(dna, "quiet")).to be(true)
      expect(Foresight::Relevance.relevant?(dna, "walkability")).to be(false)
    end

    it "keeps an aversion and a hard constraint whatever their weight" do
      expect(Foresight::Relevance.relevant?(dna, "crowds")).to be(true)
      expect(Foresight::Relevance.relevant?(dna, "car_free")).to be(true)
    end

    it "drops a dimension the traveller never mentioned" do
      expect(Foresight::Relevance.relevant?(dna, "nightlife")).to be(false)
    end

    it "filters nothing at all when the DNA cannot be reached" do
      expect(Foresight::Relevance.relevant?(nil, "nightlife")).to be(true)
    end
  end

  describe "the climate the traveller actually asked for" do
    it "takes the target from the DNA rather than assuming warm" do
      cool = { "elements" => [{ "dimension" => "climate_warm", "kind" => "preference", "target" => "cool",
                                "weight" => 0.9 }] }

      expect(Foresight::Relevance.climate_target(cool)).to eq("cool")
      expect(Foresight::Relevance.climate_target(nil)).to eq("warm")
    end

    it "turns a hot month into a risk for someone who did not want heat" do
      allow(Supply::Geo).to receive(:features).and_return("freshness" => "cached")
      allow(Supply::Climate).to receive(:normals).and_return("temp_mean_c" => 31.0, "freshness" => "cached")
      dna = { "elements" => [{ "dimension" => "climate_warm", "kind" => "preference", "target" => "cool",
                               "weight" => 0.9 }] }
      future = { "id" => "f1", "session_id" => "s1", "accommodation" => { "catalogue_id" => "p" },
                 "destination" => { "city_code" => "AER" }, "check_in" => "2026-07-08",
                 "check_out" => "2026-07-15" }
      allow(Planning::Futures).to receive(:find).and_return(future)
      allow(Planning::Sessions).to receive(:find).and_return("travel_dna" => dna)

      forecast = Foresight::Forecasts.for_future(future_id: "f1")
      expect(forecast["risks"].map { |risk| risk["risk_type"] }).to eq(%w[weather_mismatch])
    end
  end
end
