require "json"
require "bigdecimal"
require_relative "client"

module AI
  module Task
    module_function

    @logs = []

    def run(task:, input:, schema: nil, fallback: nil, response: nil)
      attempts = 0
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        attempts += 1
        raw = if response
                response.call(input)
              elsif ENV["LLM_BASE_URL"] && ENV["LLM_MODEL"]
                Client.new.call(task: task, input: input, schema: schema)
              else
                fallback ? fallback.call(input) : {}
              end
        result, usage = raw.is_a?(Array) ? raw : [raw, {}]
        validate!(result, schema) if schema
        @logs << log_entry(task, input, result, attempts, started, usage, fallback: !response && !ENV["LLM_BASE_URL"])
        result
      rescue StandardError => error
        retry if attempts < 2
        result = fallback ? fallback.call(input) : {}
        validate!(result, schema) if schema
        @logs << log_entry(task, input, result, attempts, started, {}, fallback: true).merge(error: error.message)
        result
      end
    end

    def logs; @logs; end

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
              when "boolean" then value == true || value == false
              else true
              end
      raise "AI output has invalid type" unless valid
      value
    end

    def log_entry(task, input, result, attempts, started, usage, fallback:)
      { task: task, input: input, output: result, attempts: attempts, latency_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round(3), prompt_tokens: usage["prompt_tokens"], completion_tokens: usage["completion_tokens"], cost_usd_micros: cost_usd_micros(usage), fallback: fallback }
    end

    def cost_usd_micros(usage)
      input = BigDecimal(ENV.fetch("LLM_INPUT_USD_PER_MILLION_TOKENS", "0"))
      output = BigDecimal(ENV.fetch("LLM_OUTPUT_USD_PER_MILLION_TOKENS", "0"))
      (usage.fetch("prompt_tokens", 0).to_i * input + usage.fetch("completion_tokens", 0).to_i * output).round.to_i
    end
  end
end
