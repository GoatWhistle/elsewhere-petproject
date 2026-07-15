require "rails_helper"

RSpec.describe AI::Client do
  it "calls the OpenAI-compatible chat completions endpoint with JSON schema" do
    http = instance_double(Net::HTTP)
    response = instance_double(
      Net::HTTPResponse,
      code: "200",
      body: JSON.generate(choices: [{ message: { content: JSON.generate(ok: true) } }], usage: { prompt_tokens: 3, completion_tokens: 2 })
    )
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    allow(http).to receive(:request).and_return(response)
    allow(Net::HTTP).to receive(:start).and_yield(http)

    result = described_class.new(base_url: "http://llm.test/v1", model: "test", timeout: 1).call(task: :demo, input: { text: "hello" }, schema: { "type" => "object" })

    expect(result.value).to eq("ok" => true)
    expect(result.usage).to include("prompt_tokens" => 3, "completion_tokens" => 2)
    expect(Net::HTTP).to have_received(:start).with("llm.test", 80, hash_including(open_timeout: 1, read_timeout: 1))
    expect(http).to have_received(:request) do |request|
      expect(request.path).to eq("/v1/chat/completions")
      expect(JSON.parse(request.body).dig("response_format", "type")).to eq("json_schema")
    end
  end
end
