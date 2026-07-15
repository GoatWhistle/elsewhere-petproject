require "minitest/autorun"
$LOAD_PATH.unshift(File.expand_path("../app", __dir__))
require "elsewhere"

class Phase0Test < Minitest::Test
  Request = Struct.new(:request_method, :path, :body)
  Response = Struct.new(:status, :headers, :body) do
    def []=(key, value); (self.headers ||= {})[key] = value; end
  end

  def request(method, path, payload = {})
    req = Request.new(method, path, payload.empty? ? "" : JSON.generate(payload))
    res = Response.new(200, {}, "")
    Elsewhere::HTTPApp.new(req, res).call
    [res.status, JSON.parse(res.body)]
  end

  def test_full_phase_zero_journey_through_http_layer
    Elsewhere::Store.reset!
    status, session = request("POST", "/planning-sessions", "dream_text" => "Тёплое море, тихо, до 180000 ₽", "origin" => "MOW", "date_window" => { "earliest" => "2026-07-01", "latest" => "2026-07-31", "nights_min" => 6, "nights_max" => 7 }, "party" => { "adults" => 2 })
    assert_equal 201, status
    assert session["travel_dna"]["elements"].any? { |e| e["dimension"] == "sea_access" }

    status, job = request("POST", "/planning-sessions/#{session["id"]}/futures")
    assert_equal 202, status
    assert_equal "succeeded", job["status"]
    assert_equal "futures", job["result"]["kind"]

    status, futures = request("GET", "/planning-sessions/#{session["id"]}/futures")
    assert_equal 200, status
    assert_equal 3, futures["futures"].size
    future = futures["futures"].first
    assert_equal "modeled", future["price"]["components"].find { |c| c["kind"] == "accommodation" }["fulfilment"]
    assert future["logistics"]["outbound"]
    assert future["match"]["contributions"].any?

    status, simulation = request("POST", "/futures/#{future["id"]}/simulations", "instruction" => "Сделай дешевле")
    assert_equal 202, status
    simulated = simulation["result"]["future"]
    assert_equal future["id"], simulated["parent_id"]
    assert simulated["delta"]["items"].any?

    status, forecast = request("GET", "/futures/#{future["id"]}/forecast")
    assert_equal 200, status
    assert forecast["risks"].all? { |risk| risk["evidence"].any? && risk["claim_kind"] }
    assert forecast["coverage"].any? { |coverage| coverage["assessed"] == false }
  end

  def test_ai_runner_retries_malformed_output_then_uses_fallback
    attempts = 0
    result = AI::Task.run(task: :demo, input: {}, schema: { "type" => "object", "required" => ["ok"] }, response: ->(_) { attempts += 1; {} }, fallback: ->(_) { { "ok" => true } })
    assert_equal({ "ok" => true }, result)
    assert_equal 2, attempts
  end
end
