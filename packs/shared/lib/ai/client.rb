require "json"
require "net/http"
require "uri"

module AI
  class Client
    Result = Struct.new(:value, :usage, keyword_init: true)
    class TransportError < StandardError; end

    def initialize(base_url: ENV.fetch("LLM_BASE_URL"), model: ENV.fetch("LLM_MODEL"), timeout: ENV.fetch("LLM_TIMEOUT_SECONDS", 1).to_f)
      @base_url = base_url.sub(%r{/\z}, "")
      @model = model
      @timeout = timeout
    end

    def call(task:, input:, schema:)
      uri = URI("#{@base_url}/chat/completions")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{ENV.fetch("LLM_API_KEY")}" if ENV["LLM_API_KEY"]
      request.body = JSON.generate(model: @model, temperature: 0, response_format: { type: "json_schema", json_schema: { name: task.to_s, strict: true, schema: schema } }, messages: [{ role: "user", content: JSON.generate(input) }])
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
