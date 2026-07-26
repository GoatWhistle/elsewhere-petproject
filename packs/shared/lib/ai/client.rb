require "json"
require "net/http"
require "uri"

module AI
  class Client
    Result = Struct.new(:value, :usage, keyword_init: true)
    class TransportError < StandardError; end

    def initialize(base_url: ENV.fetch("LLM_BASE_URL"), model: ENV.fetch("LLM_MODEL"), timeout: ENV.fetch("LLM_TIMEOUT_SECONDS", 1).to_f,
                   reasoning_effort: ENV["LLM_REASONING_EFFORT"].to_s.strip)
      @base_url = base_url.sub(%r{/\z}, "")
      @model = model
      @timeout = timeout
      @reasoning_effort = reasoning_effort
    end

    def call(task:, input:, schema:)
      uri = URI("#{@base_url}/chat/completions")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      # A local Ollama needs no key and the variable ships empty; an empty string is truthy in Ruby, so a naive
      # guard sends a bare "Bearer " that a stricter endpoint answers with 401.
      api_key = ENV["LLM_API_KEY"].to_s.strip
      request["Authorization"] = "Bearer #{api_key}" unless api_key.empty?
      body = { model: @model, temperature: 0, response_format: { type: "json_schema", json_schema: { name: task.to_s, strict: true, schema: schema } }, messages: [{ role: "user", content: JSON.generate(input) }] }
      # A reasoning model spends most of its latency on thinking tokens the caller never sees. `reasoning_effort`
      # is the standard OpenAI parameter, so this stays endpoint-agnostic; unset sends nothing.
      body[:reasoning_effort] = @reasoning_effort unless @reasoning_effort.empty?
      request.body = JSON.generate(body)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: @timeout, read_timeout: @timeout) { |http| http.request(request) }
      raise TransportError, "LLM HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      envelope = JSON.parse(response.body)
      content = envelope.dig("choices", 0, "message", "content")
      Result.new(value: JSON.parse(content), usage: envelope.fetch("usage", {}))
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError => error
      raise TransportError, error.message
    end
  end
end
