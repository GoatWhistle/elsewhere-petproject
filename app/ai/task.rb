require "json"

module AI
  module Task
    module_function

    @logs = []

    def run(task:, input:, schema: nil, fallback: nil)
      # The real adapter can be wired to any OpenAI-compatible endpoint. Phase 0
      # deliberately uses a deterministic fallback, so the product works offline.
      result = fallback ? fallback.call(input) : {}
      validate!(result, schema) if schema
      @logs << { task: task, latency_ms: 0, fallback: true }
      result
    rescue StandardError => error
      @logs << { task: task, error: error.message, fallback: true }
      fallback ? fallback.call(input) : {}
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
