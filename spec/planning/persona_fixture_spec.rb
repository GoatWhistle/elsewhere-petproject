require "rails_helper"

RSpec.describe "Persona regression fixtures" do
  it "contains ten named Russian Dreams with expectations" do
    personas = JSON.parse(Rails.root.join("spec/fixtures/personas/demo_ru.json").read)
    expect(personas.size).to eq(10)
    expect(personas).to all(include("id", "dream", "origin", "must_include"))
    expect(personas.map { |persona| persona.fetch("id") }.uniq.size).to eq(10)
  end
end
