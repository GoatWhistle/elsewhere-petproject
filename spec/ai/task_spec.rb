require "rails_helper"

RSpec.describe AI::Task do
  let(:schema) { { "type" => "object", "additionalProperties" => false, "properties" => { "direction" => { "type" => "string", "enum" => %w[increase decrease] } }, "required" => ["direction"] } }

  before { described_class.reset! }

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
    response = ->(_) { AI::Client::Result.new(value: { "direction" => "decrease" }, usage: { "prompt_tokens" => 100, "completion_tokens" => 20 }) }

    described_class.run(task: :instruction, input: {}, schema: schema, response: response)

    expect(described_class.logs.last).to include(prompt_tokens: 100, completion_tokens: 20, cost_usd_micros: 360)
    expect(described_class.logs.last.fetch(:latency_ms)).to be >= 0
  end

  it "preserves array values from response and fallback callables" do
    array_schema = { "type" => "array", "items" => { "type" => "object", "properties" => { "dimension" => { "type" => "string" } }, "required" => ["dimension"] } }
    elements = [{ "dimension" => "quiet" }, { "dimension" => "sea_access" }]

    expect(described_class.run(task: :dna, input: {}, schema: array_schema, response: ->(_) { elements }, fallback: ->(_) { [] })).to eq(elements)
    expect(described_class.run(task: :dna, input: {}, schema: array_schema, fallback: ->(_) { elements })).to eq(elements)
  end

  it "replaces an invalid fallback with a schema-derived neutral value" do
    result = described_class.run(task: :instruction, input: {}, schema: schema, response: ->(_) { raise "model failed" }, fallback: ->(_) { { "direction" => "invent" } })

    expect(result).to eq("direction" => "increase")
    expect(described_class.logs.last.fetch(:fallback_error)).to match(/closed vocabulary/)
  end

  it "opens the circuit after one transport failure" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LLM_BASE_URL").and_return("http://llm.test/v1")
    allow(ENV).to receive(:[]).with("LLM_MODEL").and_return("test")
    client = instance_double(AI::Client)
    allow(AI::Client).to receive(:new).and_return(client)
    expect(client).to receive(:call).once.and_raise(AI::Client::TransportError, "connection refused")
    fallback = ->(_) { { "direction" => "increase" } }

    expect(described_class.run(task: :instruction, input: {}, schema: schema, fallback: fallback)).to eq("direction" => "increase")
    expect(described_class.run(task: :instruction, input: {}, schema: schema, fallback: fallback)).to eq("direction" => "increase")
    expect(described_class.logs.last.fetch(:error)).to eq("LLM circuit open")
  end
end
