require "net/http"
require "uri"
require "json"
require "monitor"
require "zlib"
require "stringio"

module Supply
  # The single outward door: every external call goes through here, which makes "only Supply talks to the
  # outside world" checkable. Two guarantees. It never raises — a refusal, a timeout and a DNS failure all come
  # back as a Response with `error` set (provider_adapters.md, rule 2). And the per-host minimum interval is
  # enforced here rather than remembered by each caller.
  module Http
    USER_AGENT = "ElsewhereResearch/0.1 (trip-planning prototype; one-time catalogue pass; +https://github.com/elsewhere)".freeze

    # Codes that mean stop, not try again: retrying or disguising the request would circumvent bot protection
    # (C-04).
    REFUSAL = [401, 402, 403, 405, 418, 429].freeze

    Response = Struct.new(:url, :status, :body, :headers, :error, :elapsed_s, keyword_init: true) do
      def ok? = error.nil? && status.to_i >= 200 && status.to_i < 300
      def refused? = REFUSAL.include?(status)
      def json
        JSON.parse(body.to_s)
      rescue JSON::ParserError
        nil
      end
    end

    LOCK = Monitor.new
    @last_request_at = {}

    module_function

    def get(url, headers: {}, timeout: 20, min_interval: 1.0)
      request(:get, url, headers: headers, timeout: timeout, min_interval: min_interval)
    end

    def post_json(url, payload, headers: {}, timeout: 60, min_interval: 0.2)
      request(:post, url, headers: headers.merge("Content-Type" => "application/json"),
                          body: JSON.generate(payload), timeout: timeout, min_interval: min_interval)
    end

    def request(method, url, headers: {}, body: nil, timeout: 20, min_interval: 1.0)
      uri = URI.parse(url)
      throttle!(uri.host, min_interval)
      started = monotonic

      response = perform(method, uri, headers, body, timeout)
      Response.new(url: url, status: response.code.to_i, body: decode(response),
                   headers: response.each_header.to_h, elapsed_s: (monotonic - started).round(3))
    rescue StandardError => e
      # Timeout::Error, SocketError, OpenSSL errors and whatever a proxy invents: nothing escapes.
      Response.new(url: url, status: nil, body: nil, headers: {},
                   error: "#{e.class}: #{e.message}", elapsed_s: (monotonic - (started || monotonic)).round(3))
    end

    def perform(method, uri, headers, body, timeout)
      request = (method == :post ? Net::HTTP::Post : Net::HTTP::Get).new(uri)
      request["User-Agent"] = USER_AGENT
      request["Accept-Encoding"] = "gzip"
      headers.each { |key, value| request[key] = value }
      request.body = body if body

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                          open_timeout: timeout, read_timeout: timeout) do |http|
        http.request(request)
      end
    end

    def decode(response)
      raw = response.body.to_s
      return raw unless response["content-encoding"].to_s.downcase.include?("gzip")

      Zlib::GzipReader.new(StringIO.new(raw)).read
    rescue Zlib::Error
      raw
    end

    # One host, one queue. Sleeping here rather than in the caller keeps politeness out of each adapter.
    def throttle!(host, min_interval)
      return if min_interval.to_f <= 0

      wait = LOCK.synchronize do
        last = @last_request_at[host]
        gap = last ? min_interval - (monotonic - last) : 0
        @last_request_at[host] = monotonic + [gap, 0].max
        gap
      end
      sleep(wait) if wait.positive?
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
