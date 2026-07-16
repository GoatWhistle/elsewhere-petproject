require "json"
require "bigdecimal"
require_relative "client"

module AI
  module Task
    # Every call returns an Outcome, never a bare value: the fallback is a real schema-valid value and would
    # otherwise be indistinguishable from a model answer.
    Outcome = Struct.new(:value, :degraded, :reason, keyword_init: true) do
      def degraded?; degraded; end
    end

    module_function

    @logs = []
    @circuit_mutex = Mutex.new
    @circuit_open_until = nil

    def run(task:, input:, schema: nil, fallback: nil, response: nil)
      attempts = 0
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      unless response || model_configured?
        return recover(task, input, schema, fallback, attempts, started, nil, :model_not_configured)
      end
      if !response && circuit_open?
        return recover(task, input, schema, fallback, attempts, started, StandardError.new("LLM circuit open"), :circuit_open)
      end

      begin
        attempts += 1
        outcome = if response
                    raw = response.call(input)
                    raw.is_a?(Client::Result) ? raw : Client::Result.new(value: raw, usage: {})
                  else
                    Client.new.call(task: task, input: input, schema: schema)
                  end
        result = outcome.value
        validate!(result, schema) if schema
        reset_circuit! unless response
        @logs << log_entry(task, input, result, attempts, started, outcome.usage, fallback: false)
        Outcome.new(value: result, degraded: false, reason: nil)
      rescue Client::TransportError => error
        trip_circuit! unless response
        recover(task, input, schema, fallback, attempts, started, error, :transport_error)
      rescue StandardError => error
        retry if attempts < 2
        recover(task, input, schema, fallback, attempts, started, error, :invalid_output)
      end
    end

    def logs; @logs; end

    def reset!
      @logs = []
      reset_circuit!
    end

    def validate!(value, schema)
      return value unless schema
      validate_type(value, schema)
      if value.is_a?(Hash)
        Array(schema["required"]).each { |key| raise "AI output missing #{key}" unless value.key?(key) }
        if schema["additionalProperties"] == false
          unknown = value.keys - schema.fetch("properties", {}).keys
          raise "AI output has unknown keys: #{unknown.join(", ")}" if unknown.any?
        end
        schema.fetch("properties", {}).each { |key, child| validate!(value[key], child) if value.key?(key) }
      elsif value.is_a?(Array) && schema["items"]
        value.each { |item| validate!(item, schema["items"]) }
      end
      raise "AI output outside closed vocabulary" if schema["enum"] && !schema["enum"].include?(value)
      value
    end

    def validate_type(value, schema)
      type = schema["type"]
      valid = case type
              when "object" then value.is_a?(Hash)
              when "array" then value.is_a?(Array)
              when "string" then value.is_a?(String)
              when "number" then value.is_a?(Numeric)
              when "integer" then value.is_a?(Integer)
              when "boolean" then value == true || value == false
              when "null" then value.nil?
              else true
              end
      raise "AI output has invalid type" unless valid
      value
    end

    def log_entry(task, input, result, attempts, started, usage, fallback:)
      { task: task, input: input, output: result, attempts: attempts, latency_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(3), prompt_tokens: usage_value(usage, "prompt_tokens"), completion_tokens: usage_value(usage, "completion_tokens"), cost_usd_micros: cost_usd_micros(usage), fallback: fallback }
    end

    def cost_usd_micros(usage)
      input = BigDecimal(ENV.fetch("LLM_INPUT_USD_PER_MILLION_TOKENS", "0"))
      output = BigDecimal(ENV.fetch("LLM_OUTPUT_USD_PER_MILLION_TOKENS", "0"))
      (usage_value(usage, "prompt_tokens").to_i * input + usage_value(usage, "completion_tokens").to_i * output).round.to_i
    end

    def recover(task, input, schema, fallback, attempts, started, error = nil, reason = :unknown)
      fallback_error = nil
      begin
        result = fallback ? fallback.call(input) : neutral_value(schema)
        validate!(result, schema) if schema
      rescue StandardError => caught
        fallback_error = caught
        reason = :fallback_error
        result = neutral_value(schema)
      end
      entry = log_entry(task, input, result, attempts, started, {}, fallback: true)
      entry[:reason] = reason
      entry[:error] = error.message if error
      entry[:fallback_error] = fallback_error.message if fallback_error
      @logs << entry
      Outcome.new(value: result, degraded: true, reason: reason)
    end

    # Schema-derived neutrals keep a broken fallback from turning model unavailability into an error.
    def neutral_value(schema)
      return {} unless schema
      return schema["enum"].first if schema["enum"]&.any?

      case schema["type"]
      when "object"
        properties = schema.fetch("properties", {})
        Array(schema["required"]).to_h { |key| [key, neutral_value(properties[key])] }
      when "array" then []
      when "string" then ""
      when "number" then 0.0
      when "integer" then 0
      when "boolean" then false
      when "null" then nil
      else nil
      end
    end

    def model_configured?
      [ENV["LLM_BASE_URL"], ENV["LLM_MODEL"]].all? { |value| value && !value.empty? }
    end

    def circuit_open?
      @circuit_mutex.synchronize do
        @circuit_open_until = nil if @circuit_open_until && monotonic_now >= @circuit_open_until
        !@circuit_open_until.nil?
      end
    end

    def trip_circuit!
      duration = ENV.fetch("LLM_CIRCUIT_BREAKER_SECONDS", "30").to_f
      @circuit_mutex.synchronize { @circuit_open_until = monotonic_now + duration }
    end

    def reset_circuit!
      @circuit_mutex.synchronize { @circuit_open_until = nil }
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def usage_value(usage, key)
      usage[key] || usage[key.to_sym]
    end
  end
end
