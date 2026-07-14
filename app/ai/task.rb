require "json"

module AI
  module Task
    module_function

    @logs = []

    def run(task:, input:, schema: nil, fallback: nil, response: nil)
      # The real adapter can be wired to any OpenAI-compatible endpoint. Phase 0
      # uses an injected response when present, otherwise a deterministic fallback.
      attempts = 0
      begin
        attempts += 1
        result = response ? response.call(input) : (fallback ? fallback.call(input) : {})
        validate!(result, schema) if schema
        @logs << { task: task, attempts: attempts, latency_ms: 0, fallback: !response }
        result
      rescue StandardError => error
        retry if attempts < 2
        @logs << { task: task, attempts: attempts, error: error.message, fallback: true }
        fallback ? fallback.call(input) : {}
      end
    end

    def logs; @logs; end

    def validate!(value, schema)
      return value unless schema
      validate_type(value, schema)
      Array(schema["required"]).each { |key| raise "AI output missing #{key}" unless value.key?(key) }
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
  end
end
