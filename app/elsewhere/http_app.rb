require "json"

module Elsewhere
  class HTTPApp
    def initialize(request, response)
      @request = request
      @response = response
    end

    def call
      method = @request.request_method
      path = @request.path
      body = parse_body
      result, status = route(method, path, body)
      @response.status = status
      @response["Content-Type"] = "application/json"
      @response["Access-Control-Allow-Origin"] = "*"
      @response["Access-Control-Allow-Headers"] = "Content-Type"
      @response.body = JSON.generate(result)
    rescue JSON::ParserError
      render_problem(422, "Invalid JSON request")
    rescue StandardError => e
      render_problem(500, e.message)
    end

    private

    def parse_body
      raw = @request.body.to_s
      raw.empty? ? {} : JSON.parse(raw)
    end

    def route(method, path, body)
      case
      when method == "POST" && path == "/planning-sessions"
        session = Planning::Sessions.create(dream_text: body["dream_text"].to_s, origin: body["origin"] || "MOW", date_window: body["date_window"] || { "from" => "2026-07-08", "to" => "2026-07-15" }, party: body["party"] || { "adults" => 2, "children" => 0 })
        [session, 201]
      when method == "GET" && path =~ %r{\A/planning-sessions/([^/]+)\z}
        session = Planning::Sessions.find(Regexp.last_match(1)); session ? [session, 200] : problem(404, "Session not found")
      when method == "PATCH" && path =~ %r{\A/planning-sessions/([^/]+)/travel-dna\z}
        [Planning::TravelDna.update(session_id: Regexp.last_match(1), elements: body["elements"] || []), 200]
      when method == "POST" && path =~ %r{\A/planning-sessions/([^/]+)/clarifications\z}
        [Planning::TravelDna.answer_clarifications(session_id: Regexp.last_match(1), answers: body["answers"] || []), 200]
      when method == "POST" && path =~ %r{\A/planning-sessions/([^/]+)/futures\z}
        [Planning::Futures.generate(session_id: Regexp.last_match(1)), 202]
      when method == "GET" && path =~ %r{\A/planning-sessions/([^/]+)/futures\z}
        [{ "futures" => Planning::Futures.list(session_id: Regexp.last_match(1)), "diversity_note" => nil }, 200]
      when method == "GET" && path =~ %r{\A/futures/([^/]+)/forecast\z}
        [Foresight::Forecasts.for_future(future_id: Regexp.last_match(1)), 200]
      when method == "GET" && path =~ %r{\A/futures/([^/]+)\z}
        future = Planning::Futures.find(Regexp.last_match(1)); future ? [future, 200] : problem(404, "Future not found")
      when method == "POST" && path =~ %r{\A/futures/([^/]+)/simulations\z}
        [Planning::Simulator.simulate(future_id: Regexp.last_match(1), adjustments: body["adjustments"], instruction: body["instruction"], persist_to_dna: body["persist_to_travel_dna"]), 202]
      when method == "POST" && path =~ %r{\A/futures/([^/]+)/risks/([^/]+)/mitigations/([^/]+)\z}
        [Planning::Simulator.simulate(future_id: Regexp.last_match(1), adjustments: [{ "dimension" => "quiet", "direction" => "increase" }], instruction: nil, persist_to_dna: false), 202]
      when method == "GET" && path =~ %r{\A/jobs/([^/]+)\z}
        job = Elsewhere::Store.jobs[Regexp.last_match(1)]; job ? [job, 200] : problem(404, "Job not found")
      else
        problem(404, "Route not found")
      end
    end

    def problem(status, detail)
      [{ "type" => "about:blank", "title" => RacklessTitle.for(status), "status" => status, "detail" => detail }, status]
    end

    def render_problem(status, detail)
      @response.status = status
      @response["Content-Type"] = "application/problem+json"
      @response.body = JSON.generate(problem(status, detail).first)
    end

    def render_pair(pair)
      pair
    end

    def self.route_title(status)
      { 404 => "Not Found", 422 => "Unprocessable Entity", 500 => "Internal Server Error" }[status] || "Error"
    end
  end

  module RacklessTitle
    module_function
    def for(status); { 404 => "Not Found", 422 => "Unprocessable Entity", 500 => "Internal Server Error" }[status] || "Error"; end
  end
end
