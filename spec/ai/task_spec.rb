require "rails_helper"

RSpec.describe AI::Task do
  let(:schema) { { "type" => "object", "additionalProperties" => false, "properties" => { "direction" => { "type" => "string", "enum" => %w[increase decrease] } }, "required" => ["direction"] } }

  it "retries malformed nested output and falls back" do
    attempts = 0
    result = described_class.run(task: :instruction, input: {}, schema: schema, response: ->(_) { attempts += 1; { "direction" => "invent" } }, fallback: ->(_) { { "direction" => "increase" } })
    expect(attempts).to eq(2)
    expect(result).to eq("direction" => "increase")
    expect(described_class.logs.last).to include(:latency_ms, :input, :output, :cost_usd_micros)
  end

  it "logs token usage and configured cost" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("LLM_INPUT_USD_PER_MILLION_TOKENS", "0").and_return("2")
    allow(ENV).to receive(:fetch).with("LLM_OUTPUT_USD_PER_MILLION_TOKENS", "0").and_return("8")
    response = ->(_) { [{ "direction" => "decrease" }, { "prompt_tokens" => 100, "completion_tokens" => 20 }] }

    described_class.run(task: :instruction, input: {}, schema: schema, response: response)

    expect(described_class.logs.last).to include(prompt_tokens: 100, completion_tokens: 20, cost_usd_micros: 360)
    expect(described_class.logs.last.fetch(:latency_ms)).to be >= 0
  end
end
