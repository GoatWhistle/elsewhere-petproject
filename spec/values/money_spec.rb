require "rails_helper"

RSpec.describe Elsewhere::Values::Money do
  it "stores integers and adds only equal currencies" do
    expect((described_class.new(amount_minor: 100, currency: "RUB") + described_class.new(amount_minor: 50, currency: "RUB")).amount_minor).to eq(150)
    expect { described_class.new(amount_minor: 100, currency: "RUB") + described_class.new(amount_minor: 1, currency: "EUR") }.to raise_error(ArgumentError, /currency mismatch/)
  end

  it "rounds major amounts half up to minor units" do
    expect(described_class.from_major("10.005").amount_minor).to eq(1001)
    expect { described_class.new(amount_minor: 1.5, currency: "RUB") }.to raise_error(ArgumentError)
  end
end
