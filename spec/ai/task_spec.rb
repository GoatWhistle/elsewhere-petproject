require "rails_helper"

RSpec.describe AI::Task do
  let(:schema) { { "type" => "object", "additionalProperties" => false, "properties" => { "direction" => { "type" => "string", "enum" => %w[increase decrease] } }, "required" => ["direction"] } }

  it "marks a real model answer as not degraded" do
    outcome = described_class.run(task: :instruction, input: {}, schema: schema, response: ->(_) { { "direction" => "decrease" } })

    expect(outcome.value).to eq("direction" => "decrease")
    expect(outcome).not_to be_degraded
    expect(outcome.reason).to be_nil
  end

  it "retries malformed nested output, falls back, and reports the degradation" do
    attempts = 0
    outcome = described_class.run(task: :instruction, input: {}, schema: schema, response: ->(_) { attempts += 1; { "direction" => "invent" } }, fallback: ->(_) { { "direction" => "increase" } })

    expect(attempts).to eq(2)
    expect(outcome.value).to eq("direction" => "increase")
    expect(outcome).to be_degraded
    expect(outcome.reason).to eq(:invalid_output)
    expect(described_class.logs.last).to include(:latency_ms, :input, :output, :cost_usd_micros, reason: :invalid_output)
  end

  it "reports degradation when no model is configured" do
    allow(described_class).to receive(:model_configured?).and_return(false)

    outcome = described_class.run(task: :instruction, input: {}, schema: schema, fallback: ->(_) { { "direction" => "increase" } })

    expect(outcome).to be_degraded
    expect(outcome.reason).to eq(:model_not_configured)
  end

  it "logs token usage and configured cost" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("LLM_INPUT_USD_PER_MILLION_TOKENS", "0").and_return("2")
    allow(ENV).to receive(:fetch).with("LLM_OUTPUT_USD_PER_MILLION_TOKENS", "0").and_return("8")
    response = ->(_) { AI::Client::Result.new(value: { "direction" => "decrease" }, usage: { "prompt_tokens" => 100, "completion_tokens" => 20 }) }

    described_class.run(task: :instruction, input: {}, schema: schema, response: response)

    expect(described_class.logs.last).to include(prompt_tokens: 100, completion_tokens: 20, cost_usd_micros: 360)
    expect(described_class.logs.last.fetch(:latency_ms)).to be >= 0
  end

  it "preserves array values from response and fallback callables" do
    array_schema = { "type" => "array", "items" => { "type" => "object", "required" => ["dimension"] } }
    elements = [{ "dimension" => "sea_access" }, { "dimension" => "quiet" }]

    outcome = described_class.run(task: :dream_parsing, input: {}, schema: array_schema, response: ->(_) { elements })

    expect(outcome.value).to eq(elements)
    expect(outcome).not_to be_degraded
  end

  it "replaces an invalid fallback with a schema-derived neutral value" do
    outcome = described_class.run(task: :instruction, input: {}, schema: schema, response: ->(_) { raise "model down" }, fallback: ->(_) { { "direction" => "sideways" } })

    expect(outcome.value).to eq("direction" => "increase")
    expect(outcome).to be_degraded
    expect(outcome.reason).to eq(:fallback_error)
    expect(described_class.logs.last).to include(:fallback_error)
  end

  it "opens the circuit after one transport failure" do
    described_class.reset!
    allow(described_class).to receive(:model_configured?).and_return(true)
    client = instance_double(AI::Client)
    allow(AI::Client).to receive(:new).and_return(client)
    allow(client).to receive(:call).and_raise(AI::Client::TransportError, "connection refused")

    first = described_class.run(task: :instruction, input: {}, schema: schema, fallback: ->(_) { { "direction" => "increase" } })
    second = described_class.run(task: :instruction, input: {}, schema: schema, fallback: ->(_) { { "direction" => "increase" } })

    expect(first.reason).to eq(:transport_error)
    expect(second.reason).to eq(:circuit_open)
    expect(client).to have_received(:call).once
  end
end
